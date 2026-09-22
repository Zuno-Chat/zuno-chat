import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/security/known_devices_store.dart';
import 'package:zuno/core/security/new_device_alert.dart';

void main() {
  group('newDeviceAlerts', () {
    test('a device that was not there before is an alert', () {
      final alerts = newDeviceAlerts(
        knownDeviceIds: {'AAA'},
        currentDevices: {'AAA': 'Old phone', 'BBB': 'New phone'},
        ownDeviceId: 'AAA',
      );

      expect(alerts, [
        const NewDeviceAlert(deviceId: 'BBB', displayName: 'New phone'),
      ]);
    });

    test('nothing new is no alert', () {
      expect(
        newDeviceAlerts(
          knownDeviceIds: {'AAA', 'BBB'},
          currentDevices: {'AAA': null, 'BBB': null},
          ownDeviceId: 'AAA',
        ),
        isEmpty,
      );
    });

    test('the very first look alerts about nothing at all', () {
      expect(
        newDeviceAlerts(
          knownDeviceIds: null,
          currentDevices: {'AAA': null, 'BBB': null, 'CCC': null},
          ownDeviceId: 'AAA',
        ),
        isEmpty,
      );
    });

    test('a recorded-but-empty set is not the same as never looked', () {
      expect(
        newDeviceAlerts(
          knownDeviceIds: const {},
          currentDevices: {'BBB': null},
          ownDeviceId: 'AAA',
        ),
        hasLength(1),
      );
    });

    test('this device is never an alert about itself', () {
      expect(
        newDeviceAlerts(
          knownDeviceIds: const {},
          currentDevices: {'AAA': 'This device'},
          ownDeviceId: 'AAA',
        ),
        isEmpty,
      );
    });

    test('several at once are reported one by one, not as a count', () {
      final alerts = newDeviceAlerts(
        knownDeviceIds: {'AAA'},
        currentDevices: {'AAA': null, 'BBB': null, 'CCC': null},
        ownDeviceId: 'AAA',
      );

      expect(alerts.map((a) => a.deviceId), ['BBB', 'CCC']);
    });
  });

  group('newDeviceNotificationText', () {
    test('names the device, and says what to do', () {
      final text = newDeviceNotificationText(
        const NewDeviceAlert(deviceId: 'BBB', displayName: 'Pixel 8a'),
      );

      expect(text.title, 'New sign-in');
      expect(text.body, contains('Pixel 8a'));
      expect(text.body, contains('sign it out'));
    });

    test('an unnamed device falls back to its ID, never to "Unknown"', () {
      expect(
        newDeviceNotificationText(const NewDeviceAlert(deviceId: 'BBB')).body,
        contains('BBB'),
      );
      expect(
        newDeviceNotificationText(
          const NewDeviceAlert(deviceId: 'BBB', displayName: '   '),
        ).body,
        contains('BBB'),
      );
    });
  });

  group('KnownDevicesStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('never looked reads as null, not as empty', () async {
      final store = KnownDevicesStore(await SharedPreferences.getInstance());

      expect(store.knownDeviceIds('@me:example.org'), isNull);
    });

    test('remembers per account', () async {
      final store = KnownDevicesStore(await SharedPreferences.getInstance());

      await store.remember('@me:example.org', {'AAA', 'BBB'});

      expect(store.knownDeviceIds('@me:example.org'), {'AAA', 'BBB'});
      expect(store.knownDeviceIds('@other:example.org'), isNull);
    });

    test('forgetting returns it to never-looked, so the next pass reseeds', () {
      return SharedPreferences.getInstance().then((prefs) async {
        final store = KnownDevicesStore(prefs);
        await store.remember('@me:example.org', {'AAA'});

        await store.forget('@me:example.org');

        expect(store.knownDeviceIds('@me:example.org'), isNull);
      });
    });
  });
}
