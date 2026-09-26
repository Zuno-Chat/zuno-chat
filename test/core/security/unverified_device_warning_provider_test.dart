import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/security/known_devices_store.dart';
import 'package:zuno/core/security/unverified_device_warning_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_matrix.dart';

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
  late KnownDevicesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = KnownDevicesStore(prefs);
    client = buildTestClient(userId: _me, deviceId: 'THIS');
    _shareRoom(client, [_me, _alice, _bob]);
  });

  Future<ProviderContainer> watching() async {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.listen(unvouchedDeviceWarningProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  Future<void> syncFinished() async {
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    await pumpEventQueue();
  }

  Set<String> flagged(ProviderContainer container) =>
      container.read(unvouchedDeviceWarningProvider);

  test('meeting someone records their devices without a warning', () async {
    setTestDevices(client, _alice, {'A1': null});

    final container = await watching();

    expect(flagged(container), isEmpty);
    expect(store.knownDeviceIds(_alice), {'A1'});
  });

  test(
    'a new device on an account that cannot vouch for it is flagged',
    () async {
      await store.remember(_alice, {'A1'});
      setTestDevices(client, _alice, {'A1': null});
      final container = await watching();

      setTestDevices(client, _alice, {'A1': null, 'A2': null});
      await syncFinished();

      expect(flagged(container), {_alice});
    },
  );

  test('a new device on an account with an identity is not', () async {
    await store.remember(_bob, {'B1'});
    setTestDevices(client, _bob, {'B1': null, 'B2': null});
    testMasterKey(client, _bob);

    final container = await watching();

    expect(flagged(container), isEmpty);
    expect(store.knownDeviceIds(_bob), {'B1', 'B2'});
  });

  test('someone whose devices are not known yet is skipped', () async {
    final container = await watching();

    expect(flagged(container), isEmpty);
    expect(store.knownDeviceIds(_alice), isNull);
  });

  test('dismissing a warning clears only that person', () async {
    await store.remember(_alice, {'A1'});
    await store.remember(_bob, {'B1'});
    setTestDevices(client, _alice, {'A1': null, 'A2': null});
    setTestDevices(client, _bob, {'B1': null, 'B2': null});
    final container = await watching();

    container.read(unvouchedDeviceWarningProvider.notifier).dismiss(_alice);

    expect(flagged(container), {_bob});
  });

  test('signed out, nobody is looked at', () async {
    client = buildTestClient(deviceId: 'THIS');
    _shareRoom(client, [_alice]);
    setTestDevices(client, _alice, {'A1': null});

    await watching();

    expect(store.knownDeviceIds(_alice), isNull);
  });

  test('a list the server is still refreshing is not looked at', () async {
    setTestDevices(client, _alice, {'A1': null}, outdated: true);
    final container = await watching();
    expect(store.knownDeviceIds(_alice), isNull);

    setTestDevices(client, _alice, {'A1': null, 'A2': null});
    await syncFinished();

    expect(flagged(container), isEmpty);
  });

  test(
    'a device list caught half-refilled never becomes a false warning',
    () async {
      await store.remember(_alice, {'A1', 'A2'});
      setTestDevices(client, _alice, {'A1': null});
      final container = await watching();

      setTestDevices(client, _alice, {'A1': null, 'A2': null});
      await syncFinished();

      expect(flagged(container), isEmpty);
    },
  );

  test(
    'looks once the sync has finished, after the keys are refreshed',
    () async {
      await store.remember(_alice, {'A1'});
      setTestDevices(client, _alice, {'A1': null});
      final container = await watching();
      setTestDevices(client, _alice, {'A1': null, 'A2': null});

      client.onSync.add(SyncUpdate(nextBatch: 'next'));
      await pumpEventQueue();
      expect(flagged(container), isEmpty);

      await syncFinished();
      expect(flagged(container), {_alice});
    },
  );
}
