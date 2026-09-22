import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../calls/notifications/call_notification_service.dart';
import '../matrix/matrix_client_provider.dart';
import '../settings/app_preferences_provider.dart';
import 'known_devices_store.dart';
import 'new_device_alert.dart';

final knownDevicesStoreProvider = Provider<KnownDevicesStore>((ref) {
  return KnownDevicesStore(ref.watch(sharedPreferencesProvider));
});

final newDeviceAlertProvider =
    NotifierProvider<NewDeviceAlertNotifier, List<NewDeviceAlert>>(
      NewDeviceAlertNotifier.new,
    );

class NewDeviceAlertNotifier extends Notifier<List<NewDeviceAlert>> {
  bool _busy = false;

  @override
  List<NewDeviceAlert> build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onSync.stream.listen((_) => unawaited(_check(client)));
    ref.onDispose(sub.cancel);
    unawaited(_check(client));
    return const [];
  }

  void dismiss(NewDeviceAlert alert) =>
      state = state.where((a) => a != alert).toList();

  Future<void> _check(Client client) async {
    if (_busy) return;
    final userId = client.userID;
    if (userId == null) return;

    final deviceKeys = client.userDeviceKeys[userId]?.deviceKeys;
    if (deviceKeys == null || deviceKeys.isEmpty) return;

    _busy = true;
    try {
      final store = ref.read(knownDevicesStoreProvider);
      final known = store.knownDeviceIds(userId);
      final current = {
        for (final entry in deviceKeys.entries)
          entry.key: entry.value.deviceDisplayName,
      };

      final alerts = newDeviceAlerts(
        knownDeviceIds: known,
        currentDevices: current,
        ownDeviceId: client.deviceID,
      );

      await store.remember(userId, current.keys.toSet());

      if (alerts.isNotEmpty) state = [...state, ...alerts];

      for (final alert in alerts) {
        final text = newDeviceNotificationText(alert);
        try {
          await CallNotificationService.instance.showNewDevice(
            deviceId: alert.deviceId,
            title: text.title,
            body: text.body,
          );
        } catch (_) {}
      }
    } finally {
      _busy = false;
    }
  }
}
