import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_client_provider.dart';
import 'new_device_alert_provider.dart';
import 'unverified_device_warning.dart';

final unvouchedDeviceWarningProvider =
    NotifierProvider<UnvouchedDeviceWarningNotifier, Set<String>>(
      UnvouchedDeviceWarningNotifier.new,
    );

class UnvouchedDeviceWarningNotifier extends Notifier<Set<String>> {
  bool _busy = false;

  @override
  Set<String> build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onSync.stream.listen((_) => unawaited(_check(client)));
    ref.onDispose(sub.cancel);
    unawaited(_check(client));
    return const {};
  }

  void dismiss(String userId) =>
      state = state.where((id) => id != userId).toSet();

  Future<void> _check(Client client) async {
    if (_busy || client.userID == null) return;
    _busy = true;
    try {
      final store = ref.read(knownDevicesStoreProvider);
      final flagged = <String>{};

      for (final userId in peopleWhoseDevicesWeWatch(client)) {
        final keys = client.userDeviceKeys[userId];
        if (keys == null || keys.deviceKeys.isEmpty) continue;

        final current = keys.deviceKeys.keys.toSet();
        final unvouched = unvouchedNewDeviceIds(
          hasIdentity: keys.masterKey != null,
          knownDeviceIds: store.knownDeviceIds(userId),
          currentDeviceIds: current,
        );
        await store.remember(userId, current);
        if (unvouched.isNotEmpty) flagged.add(userId);
      }

      if (flagged.isNotEmpty) state = {...state, ...flagged};
    } finally {
      _busy = false;
    }
  }
}
