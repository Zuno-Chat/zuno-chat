import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/known_devices_store.dart';
import 'package:zuno/core/security/new_device_alert.dart';
import 'package:zuno/core/security/new_device_alert_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/native_method_calls.dart';

const _me = '@me:example.org';

void main() {
  late Client client;
  late SharedPreferences prefs;
  late KnownDevicesStore store;
  late RecordedNotifications notifications;

  setUp(() async {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    silenceMethodChannels(const ['zuno/calls']);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = KnownDevicesStore(prefs);
    client = buildTestClient(userId: _me, deviceId: 'THIS');
  });

  Future<ProviderContainer> watching() async {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.listen(newDeviceAlertProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  Future<void> syncFinished() async {
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await pumpEventQueue();
  }

  List<NewDeviceAlert> alerts(ProviderContainer container) =>
      container.read(newDeviceAlertProvider);

  test('the first look records the devices without alerting', () async {
    setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});

    final container = await watching();

    expect(alerts(container), isEmpty);
    expect(store.knownDeviceIds(_me), {'THIS', 'LAPTOP'});
    expect(notifications.shown, isEmpty);
  });

  test('a device that signs in later is an alert and a notification', () async {
    await store.remember(_me, {'THIS', 'LAPTOP'});
    setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});
    final container = await watching();

    setTestDevices(client, _me, {
      'THIS': null,
      'LAPTOP': 'Laptop',
      'PIXEL': 'Pixel 9',
    });
    await syncFinished();

    expect(alerts(container), [
      const NewDeviceAlert(deviceId: 'PIXEL', displayName: 'Pixel 9'),
    ]);
    expect(notifications.single.title, 'New sign-in');
    expect(notifications.single.body, contains('Pixel 9'));
  });

  test('this device never alerts about itself', () async {
    await store.remember(_me, {'LAPTOP'});
    setTestDevices(client, _me, {'THIS': null, 'LAPTOP': 'Laptop'});

    final container = await watching();

    expect(alerts(container), isEmpty);
  });

  test('dismissing an alert removes only that one', () async {
    await store.remember(_me, {'THIS'});
    setTestDevices(client, _me, {
      'THIS': null,
      'LAPTOP': 'Laptop',
      'PIXEL': 'Pixel 9',
    });
    final container = await watching();
    final laptop = alerts(container).firstWhere((a) => a.deviceId == 'LAPTOP');

    container.read(newDeviceAlertProvider.notifier).dismiss(laptop);

    expect(alerts(container).map((a) => a.deviceId), ['PIXEL']);
  });

  test('a notification that cannot be shown still leaves the alert', () async {
    await store.remember(_me, {'THIS'});
    setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});
    notifications.showError = PlatformException(code: 'blocked');

    final container = await watching();

    expect(alerts(container).map((a) => a.deviceId), ['PIXEL']);
  });

  test('signed out, nothing is looked at', () async {
    client = buildTestClient(deviceId: 'THIS');

    final container = await watching();

    expect(alerts(container), isEmpty);
    expect(prefs.getKeys(), isEmpty);
  });

  test('a list the server is still refreshing is not looked at', () async {
    setTestDevices(client, _me, {'THIS': null}, outdated: true);
    final container = await watching();
    expect(store.knownDeviceIds(_me), isNull);

    setTestDevices(client, _me, {
      'THIS': null,
      'LAPTOP': 'Laptop',
      'PIXEL': 'Pixel 9',
    });
    await syncFinished();

    expect(alerts(container), isEmpty);
    expect(store.knownDeviceIds(_me), {'THIS', 'LAPTOP', 'PIXEL'});
  });

  test(
    'a device list caught half-refilled never becomes a false alert',
    () async {
      await store.remember(_me, {'THIS', 'LAPTOP', 'PIXEL'});
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
      await store.remember(_me, {'THIS'});
      setTestDevices(client, _me, {'THIS': null});
      final container = await watching();
      setTestDevices(client, _me, {'THIS': null, 'PIXEL': 'Pixel 9'});

      client.onSync.add(SyncUpdate(nextBatch: 'next'));
      await pumpEventQueue();
      expect(alerts(container), isEmpty);

      await syncFinished();
      expect(alerts(container).map((a) => a.deviceId), ['PIXEL']);
    },
  );
}
