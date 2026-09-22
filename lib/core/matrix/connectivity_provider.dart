import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import 'connection_monitor.dart';
import 'matrix_client_provider.dart';

const homeserverProbeTimeout = Duration(seconds: 8);

const _networkChannel = EventChannel('zuno/network');

bool becameOnline(AsyncValue<bool>? previous, AsyncValue<bool> next) {
  final wasOffline = previous?.value ?? false;
  final isOffline = next.value ?? false;
  return wasOffline && !isOffline;
}

bool _isForeground(AppLifecycleState? state) =>
    state == null ||
    state == AppLifecycleState.resumed ||
    state == AppLifecycleState.inactive;

Future<bool> isHomeserverReachable(Client client) async {
  final homeserver = client.homeserver;
  if (homeserver == null) return true;
  try {
    final response = await client.httpClient
        .get(homeserver.resolveUri(Uri(path: '_matrix/client/versions')))
        .timeout(homeserverProbeTimeout);
    return response.statusCode < 500;
  } catch (_) {
    return false;
  }
}

final networkAvailabilityProvider = Provider<Stream<bool>>((ref) {
  if (!Platform.isAndroid) return const Stream.empty();
  return _networkChannel.receiveBroadcastStream().cast<bool>();
});

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final client = ref.watch(matrixClientProvider);
  final monitor = ConnectionMonitor(
    networkAvailable: ref.watch(networkAvailabilityProvider),
    syncStatus: client.onSyncStatus.stream,
    probe: () => isHomeserverReachable(client),
    foreground: _isForeground(WidgetsBinding.instance.lifecycleState),
  );
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) => monitor.setForeground(_isForeground(state)),
  );
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(monitor.dispose());
  });
  return monitor.statuses;
});

final isOfflineProvider = Provider<AsyncValue<bool>>(
  (ref) => ref
      .watch(connectionStatusProvider)
      .whenData((status) => status != ConnectionStatus.online),
);
