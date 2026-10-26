import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/alerts/known_devices_store.dart';
import 'package:zuno/core/security/alerts/security_alert.dart';
import 'package:zuno/core/security/alerts/security_alert_store.dart';
import 'package:zuno/core/security/alerts/security_alerts_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';

const _me = '@me:example.org';
const _alice = '@alice:example.org';
const _bob = '@bob:example.org';

void _shareRoom(Client client, List<String> members) {
  final room = buildTestRoom(client);
  for (final id in members) {
    room.setState(User(id, membership: 'join', room: room));
  }
  client.rooms.add(room);
}

void main() {
  late Client client;
  late SharedPreferences prefs;
  late KnownDevicesStore known;
  late RecordedNotifications notifications;

  setUp(() async {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    silenceMethodChannels(const ['zuno/calls']);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    known = KnownDevicesStore(prefs);
    client = buildTestClient(userId: _me, deviceId: 'THIS');
    _shareRoom(client, [_me, _alice, _bob]);
  });

  Future<ProviderContainer> watching() async {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        isLoggedInProvider.overrideWithValue(const AsyncData(true)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(isLoggedInProvider, (_, _) {});
    await pumpEventQueue();
    container.listen(securityAlertsProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  Future<void> syncFinished() async {
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await pumpEventQueue();
  }

  List<RecordedSecurityAlert> alerts(ProviderContainer container) =>
      container.read(securityAlertsProvider);

  group('new sign-ins', () {
    test('the first look records the devices without alerting', () async {
      setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});

      final container = await watching();

      expect(alerts(container), isEmpty);
      expect(known.knownDeviceIds(_me), {'THIS', 'LAPTOP'});
      expect(notifications.shown, isEmpty);
    });

    test(
      'a device that signs in later is an alert and a notification',
      () async {
        await known.remember(_me, {'THIS', 'LAPTOP'});
        setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});
        final container = await watching();

        setTestDevices(client, _me, {
          'THIS': null,
          'LAPTOP': 'Laptop',
          'PIXEL': 'Pixel 9',
        });
        await syncFinished();

        expect(alerts(container), [
          const NewSignInAlert(deviceId: 'PIXEL', displayName: 'Pixel 9'),
        ]);
        expect(notifications.single.title, 'New sign-in');
        expect(notifications.single.body, contains('Pixel 9'));
      },
    );

    test('this device never alerts about itself', () async {
      await known.remember(_me, {'LAPTOP'});
      setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});

      final container = await watching();

      expect(alerts(container), isEmpty);
    });

    test(
      'a notification that cannot be shown still leaves the alert',
      () async {
        await known.remember(_me, {'THIS'});
        setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});
        notifications.showError = PlatformException(code: 'blocked');

        final container = await watching();

        expect(alerts(container), [
          const NewSignInAlert(deviceId: 'PIXEL', displayName: 'Pixel 9'),
        ]);
      },
    );

    test('a list the server is still refreshing is not looked at', () async {
      setTestDevices(client, _me, {'THIS': null}, outdated: true);
      final container = await watching();
      expect(known.knownDeviceIds(_me), isNull);

      setTestDevices(client, _me, {
        'THIS': null,
        'LAPTOP': 'Laptop',
        'PIXEL': 'Pixel 9',
      });
      await syncFinished();

      expect(alerts(container), isEmpty);
      expect(known.knownDeviceIds(_me), {'THIS', 'LAPTOP', 'PIXEL'});
    });

    test(
      'a device list caught half-refilled never becomes a false alert',
      () async {
        await known.remember(_me, {'THIS', 'LAPTOP', 'PIXEL'});
        setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});
        final container = await watching();

        setTestDevices(client, _me, {
          'THIS': null,
          'LAPTOP': 'Laptop',
          'PIXEL': 'Pixel 9',
        });
        await syncFinished();

        expect(alerts(container), isEmpty);
        expect(notifications.shown, isEmpty);
      },
    );

    test(
      'looks once the sync has finished, after the keys are refreshed',
      () async {
        await known.remember(_me, {'THIS'});
        setTestDevices(client, _me, {'THIS': null});
        final container = await watching();
        setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});

        client.onSync.add(SyncUpdate(nextBatch: 'next'));
        await pumpEventQueue();
        expect(alerts(container), isEmpty);

        await syncFinished();
        expect(alerts(container), hasLength(1));
      },
    );

    test(
      'a device already approved when first seen neither alerts nor notifies',
      () async {
        await known.remember(_me, {'THIS'});
        setTestDevices(client, _me, {'THIS': null}).deviceKeys['LAPTOP'] =
            ApprovedTestDeviceKeys(testDeviceKeysJson(_me, 'LAPTOP'), client);

        final container = await watching();

        expect(alerts(container), isEmpty);
        expect(notifications.shown, isEmpty);
        expect(known.knownDeviceIds(_me), {'THIS', 'LAPTOP'});
      },
    );

    test('signing the device out closes its alert', () async {
      await known.remember(_me, {'THIS'});
      setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});
      final container = await watching();
      expect(alerts(container), hasLength(1));

      setTestDevices(client, _me, {'THIS': null});
      await syncFinished();

      expect(alerts(container), isEmpty);
      expect(SecurityAlertStore(prefs).open(_me), isEmpty);
    });
  });

  group('new devices of people who cannot vouch for them', () {
    test('meeting someone records their devices without a warning', () async {
      setTestDevices(client, _alice, {'A1': null});

      final container = await watching();

      expect(alerts(container), isEmpty);
      expect(known.knownDeviceIds(_alice), {'A1'});
    });

    test('a new device on such an account is flagged', () async {
      await known.remember(_alice, {'A1'});
      setTestDevices(client, _alice, {'A1': null});
      final container = await watching();

      setTestDevices(client, _alice, {'A1': null, 'A2': null});
      await syncFinished();

      expect(alerts(container), [
        const UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
      ]);
      expect(notifications.shown, isEmpty);
    });

    test('a new device on an account with an identity is not', () async {
      await known.remember(_bob, {'B1'});
      setTestDevices(client, _bob, {'B1': null, 'B2': null});
      testMasterKey(client, _bob);

      final container = await watching();

      expect(alerts(container), isEmpty);
      expect(known.knownDeviceIds(_bob), {'B1', 'B2'});
    });

    test('someone whose devices are not known yet is skipped', () async {
      final container = await watching();

      expect(alerts(container), isEmpty);
      expect(known.knownDeviceIds(_alice), isNull);
    });
  });

  group('recovery resets', () {
    Future<ProviderContainer> watchingWithIdentity() async {
      setTestDevices(client, _me, {'THIS': null});
      testMasterKey(client, _me, publicKey: 'OLD');
      final container = await watching();
      expect(alerts(container), isEmpty);
      return container;
    }

    test(
      'a new identity this device did not make is an alert and a notification',
      () async {
        final container = await watchingWithIdentity();

        testMasterKey(client, _me, publicKey: 'NEW');
        await syncFinished();

        expect(alerts(container), const [RecoveryResetAlert('NEW')]);
        expect(
          notifications.single.title,
          'Your recovery code was replaced on another device',
        );
      },
    );

    test('approving this device afterwards closes it', () async {
      final container = await watchingWithIdentity();
      testMasterKey(client, _me, publicKey: 'NEW');
      await syncFinished();
      expect(alerts(container), hasLength(1));

      client.userDeviceKeys[_me]!.deviceKeys['THIS'] =
          OwnerSignedTestDeviceKeys(testDeviceKeysJson(_me, 'THIS'), client);
      await syncFinished();

      expect(alerts(container), isEmpty);
    });

    test('replacing the code on this device never alarms', () async {
      final container = await watchingWithIdentity();
      final hold = container.read(ownIdentityResetHoldProvider.notifier);

      hold.hold();
      testMasterKey(client, _me, publicKey: 'NEW');
      await syncFinished();
      await hold.release();
      await syncFinished();

      expect(alerts(container), isEmpty);
      expect(notifications.shown, isEmpty);
    });
  });

  test('a new sign-in carries where and when the server last saw it', () async {
    client =
        buildTestClient(
            userId: _me,
            deviceId: 'THIS',
            httpClient: FakeHttpClient((request) async {
              if (request.url.path.endsWith('/devices/PIXEL')) {
                return http.Response(
                  jsonEncode({
                    'device_id': 'PIXEL',
                    'last_seen_ip': '81.2.69.160',
                    'last_seen_ts': 1760000000000,
                  }),
                  200,
                );
              }
              return http.Response('{}', 404);
            }),
          )
          ..homeserver = Uri.parse('https://example.org')
          ..accessToken = 'token';
    await known.remember(_me, {'THIS'});
    setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});

    final container = await watching();

    expect(alerts(container), [
      NewSignInAlert(
        deviceId: 'PIXEL',
        displayName: 'Pixel 9',
        ipAddress: '81.2.69.160',
        seenAt: DateTime.fromMillisecondsSinceEpoch(1760000000000),
      ),
    ]);
  });

  group('open alerts', () {
    test('are still open after a restart', () async {
      await known.remember(_me, {'THIS'});
      setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});
      final first = await watching();
      expect(alerts(first), hasLength(1));
      first.dispose();

      final second = await watching();

      expect(alerts(second), [
        const NewSignInAlert(deviceId: 'PIXEL', displayName: 'Pixel 9'),
      ]);
      expect(notifications.shown, hasLength(1));
    });

    test('dismissing one keeps the rest, across a restart too', () async {
      await known.remember(_me, {'THIS'});
      await known.remember(_alice, {'A1'});
      setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});
      setTestDevices(client, _alice, {'A1': null, 'A2': null});
      final container = await watching();

      await container
          .read(securityAlertsProvider.notifier)
          .dismiss(alerts(container).whereType<NewSignInAlert>().single);

      const remaining = [
        UnvouchedDeviceAlert(userId: _alice, deviceIds: {'A2'}),
      ];
      expect(alerts(container), remaining);
      expect(SecurityAlertStore(prefs).open(_me), remaining);
    });

    test('signed out, nothing is looked at', () async {
      client = buildTestClient(deviceId: 'THIS');
      _shareRoom(client, [_alice]);
      setTestDevices(client, _alice, {'A1': null});

      final container = await watching();

      expect(alerts(container), isEmpty);
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
