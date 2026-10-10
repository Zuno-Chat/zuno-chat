import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/active_sessions_page.dart';
import 'package:zuno/features/settings/presentation/sign_in_another_device_page.dart';
import 'package:zuno/features/verification/presentation/approve_this_device_page.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/fake_call_session.dart';
import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/security_facts.dart';
import '../../../helpers/uia_challenge.dart';
import '../../verification/presentation/verification_harness.dart';

const _me = '@alice:example.org';
const _here = 'HERE';

class _Keys extends DeviceKeys {
  _Keys(Client client, String deviceId, {this.approved = false})
    : super.fromJson(testDeviceKeysJson(_me, deviceId), client);

  final bool approved;
  Future<KeyVerification> Function()? onStart;

  @override
  bool get verified => approved;

  @override
  Future<KeyVerification> startVerification() =>
      onStart?.call() ?? Future.error(StateError('no encryption'));
}

class _DevicesClient extends Client {
  _DevicesClient() : super('test', database: FakeDatabaseApi()) {
    setUserId(_me);
  }

  @override
  String? get deviceID => _here;

  List<Device> devices = [];
  Object? devicesError;
  Completer<void>? devicesGate;
  int deviceReads = 0;
  final deletions = <List<String>>[];
  final passwords = <String>[];
  Object? deleteError;
  int logouts = 0;
  Object? logoutError;
  final journal = <String>[];
  int tokenRequests = 0;

  void setKeys(List<_Keys> keys) =>
      userDeviceKeys[_me] = DeviceKeysList(_me, this)
        ..deviceKeys = {for (final key in keys) key.deviceId!: key};

  @override
  Future<List<Device>?> getDevices() async {
    deviceReads++;
    await devicesGate?.future;
    final error = devicesError;
    if (error != null) throw error;
    return devices;
  }

  @override
  Future<void> updateUserDeviceKeys({Set<String>? additionalUsers}) async {}

  Future<void> _delete(List<String> ids, AuthenticationData? auth) async {
    if (auth == null) throw uiaPasswordChallenge();
    passwords.add((auth as AuthenticationPassword).password);
    final error = deleteError;
    if (error != null) throw error;
    deletions.add(ids);
    devices = devices.where((d) => !ids.contains(d.deviceId)).toList();
    userDeviceKeys[_me]?.deviceKeys.removeWhere((id, _) => ids.contains(id));
  }

  @override
  Future<void> deleteDevices(
    List<String> devices, {
    AuthenticationData? auth,
  }) => _delete(devices, auth);

  @override
  Future<void> deleteDevice(String deviceId, {AuthenticationData? auth}) =>
      _delete([deviceId], auth);

  @override
  Future<void> logout() async {
    logouts++;
    final error = logoutError;
    if (error != null) throw error;
    journal.add('logged out');
  }

  @override
  Future<GenerateLoginTokenResponse> generateLoginToken({
    AuthenticationData? auth,
  }) async {
    tokenRequests++;
    throw uiaPasswordChallenge();
  }
}

final _lastWeek = DateTime(2026, 9, 20, 14, 5).millisecondsSinceEpoch;
final _yesterday = DateTime(2026, 9, 26, 9, 30).millisecondsSinceEpoch;

void main() {
  late _DevicesClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = _DevicesClient();
    silenceMethodChannels(const ['zuno/background_sync']);
  });

  Future<void> pullToRefresh(WidgetTester tester) =>
      tester.fling(find.text('Signed in'), const Offset(0, 800), 1000);

  void threeDevices({bool pixelApproved = true}) {
    client
      ..devices = [
        Device(
          deviceId: _here,
          displayName: 'Zuno on Android',
          lastSeenTs: _yesterday,
          lastSeenIp: '10.0.0.1',
        ),
        Device(
          deviceId: 'TABLET',
          displayName: 'Tablet',
          lastSeenTs: _lastWeek,
          lastSeenIp: '10.0.0.2',
        ),
        Device(
          deviceId: 'PIXEL',
          displayName: 'Pixel',
          lastSeenTs: _yesterday,
          lastSeenIp: '10.0.0.3',
        ),
      ]
      ..setKeys([
        _Keys(client, _here, approved: true),
        _Keys(client, 'TABLET'),
        _Keys(client, 'PIXEL', approved: pixelApproved),
      ]);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    bool? identityKeysHere = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountSecurityFactsProvider.overrideWith(
            (ref) => identityKeysHere == null
                ? const Stream.empty()
                : Stream.value(
                    securityFacts(thisDeviceHasIdentityKeys: identityKeysHere),
                  ),
          ),
        ],
        child: const MaterialApp(home: ActiveSessionsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tileOf(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));

  String subtitleOf(WidgetTester tester, String name) =>
      (tester.widget<ListTile>(tileOf(name).first).subtitle! as Text).data!;

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(TextButton, label).last);
    await tester.pumpAndSettle();
  }

  Future<void> enterPassword(WidgetTester tester, String password) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      password,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('puts this device first, then the most recently active', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester);

      final tops = [
        'Zuno on Android',
        'Pixel',
        'Tablet',
      ].map((name) => tester.getRect(find.text(name)).top).toList();
      expect(tops, [...tops]..sort());
      expect(
        find.descendant(
          of: tileOf('Zuno on Android'),
          matching: find.text('This device'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('says which devices are approved and when each was last '
        'active', (tester) async {
      threeDevices();
      await pumpPage(tester);

      expect(
        subtitleOf(tester, 'Zuno on Android'),
        startsWith('Approved · Last active Sep 26, 2026 at 9:30 AM'),
      );
      expect(subtitleOf(tester, 'Tablet'), startsWith('Not approved yet'));
      expect(subtitleOf(tester, 'Pixel'), startsWith('Approved'));
    });

    testWidgets('a device with no name or activity shows its ID', (
      tester,
    ) async {
      client
        ..devices = [Device(deviceId: _here), Device(deviceId: 'OLDPHONE')]
        ..setKeys([_Keys(client, _here, approved: true)]);
      await pumpPage(tester);

      expect(find.text('OLDPHONE'), findsOneWidget);
      expect(
        subtitleOf(tester, 'OLDPHONE'),
        'Not approved yet · Last activity unknown',
      );
    });

    testWidgets('IP addresses stay hidden until asked for', (tester) async {
      threeDevices();
      await pumpPage(tester);

      expect(find.textContaining('10.0.0.'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Show IP'));
      await tester.pump();

      expect(subtitleOf(tester, 'Tablet'), endsWith(' · 10.0.0.2'));

      await tester.tap(find.widgetWithText(TextButton, 'Hide IP'));
      await tester.pump();

      expect(find.textContaining('10.0.0.'), findsNothing);
    });

    testWidgets('while the approval state loads, nothing is called approved', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester, identityKeysHere: null);

      expect(subtitleOf(tester, 'Zuno on Android'), startsWith('Checking…'));
      expect(
        subtitleOf(tester, 'Pixel'),
        startsWith('Cannot check from this device'),
      );
      expect(find.text('Approve this device'), findsNothing);
    });

    testWidgets('with no devices at all it says so', (tester) async {
      await pumpPage(tester);

      expect(find.text('No devices found.'), findsOneWidget);
      expect(find.text('Sign out this device'), findsNothing);
    });

    testWidgets('a failed load says so instead of claiming there are no '
        'devices', (tester) async {
      client.devicesError = Exception('offline');
      await pumpPage(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('No devices found.'), findsNothing);
      expect(
        find.text('Could not load your devices. Pull down to try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed refresh keeps the list and says so', (tester) async {
      threeDevices();
      await pumpPage(tester);
      client.devicesError = Exception('offline');

      await pullToRefresh(tester);
      await tester.pumpAndSettle();

      expect(find.text('Pixel'), findsOneWidget);
      expect(find.text('Could not refresh your devices.'), findsOneWidget);
    });

    testWidgets('pulling to refresh keeps the list on screen', (tester) async {
      threeDevices();
      await pumpPage(tester);
      client.devicesGate = Completer();

      await pullToRefresh(tester);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(client.deviceReads, 2);
      expect(find.text('Pixel'), findsOneWidget);

      client.devicesGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('this device', () {
    testWidgets('an unapproved one offers approval and rechecks after', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester, identityKeysHere: false);
      expect(
        subtitleOf(tester, 'Zuno on Android'),
        startsWith('Not approved yet'),
      );

      await tester.tap(find.text('Approve this device'));
      await tester.pumpAndSettle();
      expect(find.byType(ApproveThisDevicePage), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(client.deviceReads, 2);
    });

    testWidgets('an approved one is not offered approval', (tester) async {
      threeDevices();
      await pumpPage(tester);

      expect(find.text('Approve this device'), findsNothing);
    });

    testWidgets('signing out asks first, then signs out', (tester) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(find.text('Sign out this device'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of this device?'), findsOneWidget);
      expect(find.textContaining('Without a recovery code'), findsOneWidget);

      await confirm(tester, 'Sign out');

      expect(client.logouts, 1);
    });

    testWidgets('signing out mid-call ends the call before the token goes', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester);
      ProviderScope.containerOf(tester.element(find.byType(ActiveSessionsPage)))
          .read(activeCallProvider.notifier)
          .set(
            FakeCallSession(
              room: buildCallRoom(),
              kind: CallKind.voice,
              journal: client.journal,
            ),
          );

      await tester.tap(find.text('Sign out this device'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Sign out');

      expect(client.journal, ['call ended', 'logged out']);
    });

    testWidgets('Cancel keeps it signed in', (tester) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(find.text('Sign out this device'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Cancel');

      expect(client.logouts, 0);
    });

    testWidgets('a failed sign-out says so', (tester) async {
      threeDevices();
      client.logoutError = Exception('offline');
      await pumpPage(tester);

      await tester.tap(find.text('Sign out this device'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Sign out');

      expect(find.text('Not signed out. Try again.'), findsOneWidget);
    });
  });

  group('signing out other devices', () {
    testWidgets('everywhere else counts them, asks for the password, and '
        'refreshes the list', (tester) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(find.text('Sign out everywhere else'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of 2 other devices?'), findsOneWidget);

      await confirm(tester, 'Sign out');
      expect(find.text('Confirm your password'), findsOneWidget);

      await enterPassword(tester, 'hunter2');

      expect(client.passwords, ['hunter2']);
      expect(client.deletions.single, unorderedEquals(['TABLET', 'PIXEL']));
      expect(find.text('Pixel'), findsNothing);
      expect(find.text('Sign out everywhere else'), findsNothing);
    });

    testWidgets('one other device is counted as one', (tester) async {
      client
        ..devices = [Device(deviceId: _here), Device(deviceId: 'PIXEL')]
        ..setKeys([_Keys(client, _here, approved: true)]);
      await pumpPage(tester);

      await tester.tap(find.text('Sign out everywhere else'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out of 1 other device?'), findsOneWidget);
    });

    testWidgets('one device at a time, by name', (tester) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: tileOf('Tablet'),
          matching: find.byTooltip('Sign out of this device'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign out of "Tablet"?'), findsOneWidget);

      await confirm(tester, 'Sign out');
      await enterPassword(tester, 'hunter2');

      expect(client.deletions, [
        ['TABLET'],
      ]);
      expect(find.text('Tablet'), findsNothing);
      expect(find.text('Pixel'), findsOneWidget);
    });

    testWidgets('Cancel in the confirmation signs nothing out', (tester) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(find.text('Sign out everywhere else'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Cancel');

      expect(find.text('Confirm your password'), findsNothing);
      expect(client.deletions, isEmpty);
    });

    testWidgets('cancelling the password signs nothing out, quietly', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(find.text('Sign out everywhere else'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Sign out');
      await confirm(tester, 'Cancel');

      expect(client.deletions, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Pixel'), findsOneWidget);
    });

    testWidgets('a server failure says so', (tester) async {
      threeDevices();
      client.deleteError = Exception('offline');
      await pumpPage(tester);

      await tester.tap(find.text('Sign out everywhere else'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Sign out');
      await enterPassword(tester, 'hunter2');

      expect(find.text('Not signed out. Try again.'), findsOneWidget);
      expect(find.text('Pixel'), findsOneWidget);
    });
  });

  group('approving another device', () {
    testWidgets('only an unapproved one offers it', (tester) async {
      threeDevices();
      await pumpPage(tester);

      expect(
        find.descendant(of: tileOf('Tablet'), matching: find.text('Approve')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tileOf('Pixel'), matching: find.text('Approve')),
        findsNothing,
      );
    });

    testWidgets('opens the check as the own-device kind and rechecks after', (
      tester,
    ) async {
      threeDevices();
      final verification = FakeKeyVerification(userId: _me);
      (client.userDeviceKeys[_me]!.deviceKeys['TABLET']! as _Keys).onStart =
          () async => verification;
      await pumpPage(tester);

      await tester.tap(
        find.descendant(of: tileOf('Tablet'), matching: find.text('Approve')),
      );
      await settle(tester);

      final page = tester.widget<VerificationPage>(
        find.byType(VerificationPage),
      );
      expect(page.keyVerification, same(verification));
      expect(page.isOwnDevice, isTrue);

      await tester.pageBack();
      await settle(tester);

      expect(find.byType(VerificationPage), findsNothing);
      expect(client.deviceReads, 2);
    });

    testWidgets('a check that cannot start says so', (tester) async {
      threeDevices();
      await pumpPage(tester);

      await tester.tap(
        find.descendant(of: tileOf('Tablet'), matching: find.text('Approve')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Could not start approving that device. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(VerificationPage), findsNothing);
    });
  });

  group('Sign in on another device', () {
    Future<void> openAndCancel(WidgetTester tester) async {
      await tester.tap(find.text('Sign in on another device'));
      await settle(tester);
      expect(find.byType(SignInAnotherDevicePage), findsOneWidget);
      expect(find.text('Confirm your password'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('its password prompt is asked once, not by this page too', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester);

      await openAndCancel(tester);

      expect(client.tokenRequests, 1);
      expect(find.byType(SignInAnotherDevicePage), findsNothing);
      expect(client.deviceReads, 2);
    });

    testWidgets('after it this page answers its own password prompts again', (
      tester,
    ) async {
      threeDevices();
      await pumpPage(tester);
      await openAndCancel(tester);

      await tester.tap(find.text('Sign out everywhere else'));
      await tester.pumpAndSettle();
      await confirm(tester, 'Sign out');

      expect(find.text('Confirm your password'), findsOneWidget);
      await enterPassword(tester, 'hunter2');
      expect(client.deletions, hasLength(1));
    });
  });
}
