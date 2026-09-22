import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/call_notification_router.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';

class _SendCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<User?> getUser(String userId, Room room) async => null;

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;
  late ProviderContainer container;

  void mockLaunchAction({required String action, required String callId}) {
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method != 'getNotificationAppLaunchDetails') return null;
      return <String, Object?>{
        'notificationLaunchedApp': true,
        'notificationResponse': <String, Object?>{
          'notificationId': 4002,
          'actionId': action,
          'notificationResponseType': 1,
          'payload': jsonEncode({
            'roomId': room.id,
            'callId': callId,
            'callerId': '@bob:example.org',
            'isVideo': false,
          }),
        },
      };
    });
  }

  void mockNoLaunchAction() {
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => <String, Object?>{'notificationLaunchedApp': false},
    );
  }

  setUp(() async {
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    client = Client(
      'test',
      database: _SendCapableFakeDatabaseApi(),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);

    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.read(callNotificationRouterProvider);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
  });

  test('returns false and does nothing when there is no launch action', () async {
    mockNoLaunchAction();

    final acted = await container
        .read(callNotificationRouterProvider.notifier)
        .recheckLaunchAction();

    expect(acted, isFalse);
  });

  test(
    'declines the call and marks it resolved when the launch action is Decline',
    () async {
      mockLaunchAction(action: 'decline', callId: 'call1');

      final acted = await container
          .read(callNotificationRouterProvider.notifier)
          .recheckLaunchAction();

      expect(acted, isTrue);
      expect(
        container.read(resolvedCallIdsProvider),
        contains('call1'),
        reason: 'declineCall\'s real room.sendEvent should have gone '
            'through and the call marked resolved',
      );
    },
  );

  test(
    'calling it again for the same already-resolved call is a safe no-op',
    () async {
      mockLaunchAction(action: 'decline', callId: 'call1');
      final router = container.read(callNotificationRouterProvider.notifier);
      await router.recheckLaunchAction();

      final acted = await router.recheckLaunchAction();

      expect(acted, isTrue, reason: 'a response was still decoded...');
      expect(container.read(resolvedCallIdsProvider), {'call1'});
    },
  );

  group('ongoing-call hang up', () {
    const callsChannel = MethodChannel('zuno/calls');

    Future<void> sendHangUpFromPlatform() async {
      await messenger.handlePlatformMessage(
        callsChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('hangUpCall'),
        ),
        null,
      );
    }

    setUp(() async {
      messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
        if (call.method == 'initialize') return true;
        return null;
      });
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    test('ends the active call', () async {
      final session = CallSession.forIncoming(
        room: room,
        callId: 'ongoing1',
        kind: CallKind.voice,
      );
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);

      await sendHangUpFromPlatform();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
    });

    test('is a no-op when there is no active call', () async {
      container.read(activeCallProvider.notifier).set(null);

      await sendHangUpFromPlatform();
      await pumpEventQueue();

      expect(container.read(activeCallProvider), isNull);
    });

    test('a second hang up for an already-ended call is harmless', () async {
      final session = CallSession.forIncoming(
        room: room,
        callId: 'ongoing2',
        kind: CallKind.voice,
      );
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);

      await sendHangUpFromPlatform();
      await pumpEventQueue();
      await sendHangUpFromPlatform();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
    });
  });
}
