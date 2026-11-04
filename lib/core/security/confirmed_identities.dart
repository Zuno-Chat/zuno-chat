import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../matrix/client/matrix_client_provider.dart';
import '../matrix/sync/finished_syncs.dart';
import 'confirmed_identity_store.dart';
import 'security_providers.dart';
import 'user_trust.dart';

Future<void> rememberConfirmedIdentity(
  ConfirmedIdentityStore store,
  DeviceKeysList keys,
) async {
  final userId = keys.userId;
  if (userId == keys.client.userID) return;
  final identity = keys.masterKey;
  final key = identity?.ed25519Key;
  if (identity == null || key == null) return;
  final checkedHere = identity.directVerified;
  if (store.confirmedIdentityKey(userId) == key &&
      (store.confirmedAt(userId) != null || !checkedHere)) {
    return;
  }
  if (!confirmedByOwnAccount(identity)) return;
  await store.remember(userId, key, at: checkedHere ? clock.now() : null);
}

final confirmedIdentityTrackerProvider = Provider<void>((ref) {
  final client = ref.watch(matrixClientProvider);
  final store = ref.watch(confirmedIdentityStoreProvider);
  final sub = finishedSyncs(client)
      .listen((_) => unawaited(_rememberAll(client, store)));
  ref.onDispose(sub.cancel);
  unawaited(_rememberAll(client, store));
});

Future<void> _rememberAll(Client client, ConfirmedIdentityStore store) async {
  for (final keys in List.of(client.userDeviceKeys.values)) {
    await runBestEffort(
      () => rememberConfirmedIdentity(store, keys),
      label: 'remember a confirmed person',
    );
  }
}
