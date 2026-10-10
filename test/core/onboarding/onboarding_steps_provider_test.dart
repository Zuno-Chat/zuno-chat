import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/fake_permissions.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/preferences_container.dart';

const _userId = '@alex:example.org';

class _SessionClient extends Client {
  _SessionClient() : super('test', database: FakeDatabaseApi());

  String? user;
  String? syncToken;

  @override
  String? get userID => user;

  @override
  String? get prevBatch => syncToken;
}

const _settled = AccountSecurityFacts(
  recoveryExists: true,
  thisDeviceHasIdentityKeys: true,
  keyBackupExists: true,
  keyBackupUsableHere: true,
  unapprovedOtherDevices: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installFakePermissions();
    recordMethodChannel(
      'zuno/background_sync',
      reply: (call) => switch (call.method) {
        'isIgnoringBatteryOptimizations' => false,
        'hasAutostartSettings' => false,
        _ => null,
      },
    );
  });

  Future<ProviderContainer> containerFor(
    Client client,
    PlatformCapabilities capabilities, {
    Map<String, Object> prefs = const {},
    AccountSecurityFacts facts = _settled,
    bool synced = false,
  }) => containerWithPreferences(
    prefs,
    overrides: [
      matrixClientProvider.overrideWithValue(client),
      accountSecurityFactsProvider.overrideWith((ref) => Stream.value(facts)),
      platformCapabilitiesProvider.overrideWithValue(capabilities),
      if (synced) firstSyncProvider.overrideWith((ref) async {}),
    ],
  );

  Future<List<OnboardingStep>> stepsOn(
    PlatformCapabilities capabilities, {
    Map<String, Object> prefs = const {
      'onboarding.shown.$_userId': ['confirmPeople'],
    },
    AccountSecurityFacts facts = _settled,
    void Function(Client client)? addRooms,
  }) async {
    final client = buildTestClient(userId: _userId);
    addRooms?.call(client);
    final container = await containerFor(
      client,
      capabilities,
      prefs: prefs,
      facts: facts,
      synced: true,
    );
    container.listen(onboardingStepsProvider, (_, _) {});
    return container.read(onboardingStepsProvider.future);
  }

  group('on a fresh sign-in', () {
    test('decides nothing until the first sync has finished', () async {
      final client = buildTestClient(userId: _userId);
      final container = await containerFor(client, iosCapabilities);
      container.listen(onboardingStepsProvider, (_, _) {});
      final steps = container.read(onboardingStepsProvider.future);
      var decided = false;
      unawaited(steps.then((_) => decided = true));
      await pumpEventQueue();

      expect(decided, isFalse);

      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));

      expect(await steps, [OnboardingStep.confirmPeople]);
    });

    test('signing out and in again in one process onboards the next '
        'account', () async {
      final client = _SessionClient()
        ..user = '@first:example.org'
        ..syncToken = 's1'
        ..accessToken = 'a1';
      final container = await containerFor(
        client,
        iosCapabilities,
        prefs: {
          'onboarding.shown.@first:example.org': ['confirmPeople'],
        },
      );
      final firstRoomList = container.listen(
        onboardingStepsProvider,
        (_, _) {},
      );
      expect(await container.read(onboardingStepsProvider.future), isEmpty);

      client
        ..user = null
        ..syncToken = null
        ..accessToken = null;
      client.onLoginStateChanged.add(LoginState.loggedOut);
      await pumpEventQueue();
      firstRoomList.close();

      client
        ..user = '@next:example.org'
        ..accessToken = 'a2';
      client.onLoginStateChanged.add(LoginState.loggedIn);
      await pumpEventQueue();
      final seen = <List<OnboardingStep>>[];
      container.listen(onboardingStepsProvider, (_, next) {
        if (!next.isLoading && next.hasValue) seen.add(next.requireValue);
      });
      client.syncToken = 's2';
      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
      await pumpEventQueue();

      expect(seen, [
        [OnboardingStep.confirmPeople],
      ]);
    });
  });

  group('recovery waits for a conversation', () {
    const noRecovery = AccountSecurityFacts(
      recoveryExists: false,
      thisDeviceHasIdentityKeys: true,
      keyBackupExists: false,
      keyBackupUsableHere: false,
      unapprovedOtherDevices: 0,
    );

    Room joined(Client client, String id, {bool community = false}) {
      final room = buildTestRoom(client, id: id)..membership = Membership.join;
      if (community) {
        room.setState(
          StrippedStateEvent(
            type: EventTypes.RoomCreate,
            senderId: _userId,
            stateKey: '',
            content: {'type': 'm.space'},
          ),
        );
      }
      client.rooms.add(room);
      return room;
    }

    test('a community alone is not one', () async {
      final steps = await stepsOn(
        iosCapabilities,
        facts: noRecovery,
        addRooms: (client) => joined(client, '!club:x', community: true),
      );

      expect(steps, isNot(contains(OnboardingStep.setUpRecovery)));
    });

    test('a chat is', () async {
      final steps = await stepsOn(
        iosCapabilities,
        facts: noRecovery,
        addRooms: (client) => joined(client, '!chat:x'),
      );

      expect(steps, contains(OnboardingStep.setUpRecovery));
    });
  });

  test('Android asks how messages should arrive', () async {
    expect(await stepsOn(androidCapabilities), [OnboardingStep.deliveryMethod]);
  });

  test('iOS has one way for messages to arrive, so it asks nothing', () async {
    expect(await stepsOn(iosCapabilities), isEmpty);
  });

  group('once the method is chosen', () {
    const unifiedPushChosen = <String, Object>{
      'settings.notification_delivery_mode': 'unifiedPush',
      'onboarding.shown.$_userId': ['deliveryMethod', 'confirmPeople'],
    };

    test('Android asks for the battery exemption UnifiedPush needs', () async {
      expect(await stepsOn(androidCapabilities, prefs: unifiedPushChosen), [
        OnboardingStep.batteryExemption,
      ]);
    });

    test('a platform without a battery exemption never asks for one', () async {
      expect(
        await stepsOn(
          capabilitiesLike(androidCapabilities, batteryExemption: false),
          prefs: unifiedPushChosen,
        ),
        isEmpty,
      );
    });

    test(
      'iOS never asks, even with UnifiedPush left over in storage',
      () async {
        expect(
          await stepsOn(iosCapabilities, prefs: unifiedPushChosen),
          isEmpty,
        );
      },
    );
  });
}
