import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/security/alerts/known_devices_store.dart';
import 'package:zuno/core/security/alerts/security_alert.dart';
import 'package:zuno/core/security/alerts/security_alert_store.dart';

const _me = '@me:example.org';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SecurityAlertStore', () {
    test('open alerts survive a restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final alerts = [
        const RecoveryResetAlert('NEW'),
        NewSignInAlert(
          deviceId: 'PIXEL',
          displayName: 'Pixel 9',
          ipAddress: '81.2.69.160',
          seenAt: DateTime.fromMillisecondsSinceEpoch(1760000000000),
        ),
        const NewSignInAlert(deviceId: 'LAPTOP'),
        const UnvouchedDeviceAlert(
          userId: '@alice:example.org',
          deviceIds: {'A2', 'A3'},
        ),
      ];
      await SecurityAlertStore(prefs).save(_me, alerts);

      expect(SecurityAlertStore(prefs).open(_me), alerts);
    });

    test('alerts belong to the account that raised them', () async {
      final store = SecurityAlertStore(await SharedPreferences.getInstance());

      await store.save(_me, const [NewSignInAlert(deviceId: 'PIXEL')]);

      expect(store.open('@other:example.org'), isEmpty);
    });

    test('saving none leaves nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SecurityAlertStore(prefs);
      await store.save(_me, const [NewSignInAlert(deviceId: 'PIXEL')]);

      await store.save(_me, const []);

      expect(store.open(_me), isEmpty);
      expect(prefs.getKeys(), isEmpty);
    });

    test('an alert kind this version does not know is skipped', () async {
      SharedPreferences.setMockInitialValues({
        'security.alerts.$_me': jsonEncode([
          {'kind': 'fromTheFuture'},
          {'kind': 'newSignIn', 'deviceId': 'PIXEL'},
        ]),
      });
      final store = SecurityAlertStore(await SharedPreferences.getInstance());

      expect(store.open(_me), const [NewSignInAlert(deviceId: 'PIXEL')]);
    });
  });

  group('KnownDevicesStore', () {
    test('remembers per account, an account never looked at reading as null, '
        'not as empty', () async {
      final store = KnownDevicesStore(await SharedPreferences.getInstance());

      await store.remember(_me, {'AAA', 'BBB'});

      expect(store.knownDeviceIds(_me), {'AAA', 'BBB'});
      expect(store.knownDeviceIds('@other:example.org'), isNull);
    });

    test(
      'remembering adds to what is known and never forgets a device',
      () async {
        final store = KnownDevicesStore(await SharedPreferences.getInstance());
        await store.remember(_me, {'AAA', 'BBB'});

        await store.remember(_me, {'AAA'});
        await store.remember(_me, {'AAA', 'CCC'});

        expect(store.knownDeviceIds(_me), {'AAA', 'BBB', 'CCC'});
      },
    );

    test(
      'remembering an empty first look still counts as having looked',
      () async {
        final store = KnownDevicesStore(await SharedPreferences.getInstance());

        await store.remember(_me, {});

        expect(store.knownDeviceIds(_me), isEmpty);
      },
    );

    test(
      'forgetting returns it to never-looked, so the next pass reseeds',
      () async {
        final store = KnownDevicesStore(await SharedPreferences.getInstance());
        await store.remember(_me, {'AAA'});

        await store.forget(_me);

        expect(store.knownDeviceIds(_me), isNull);
      },
    );
  });
}
