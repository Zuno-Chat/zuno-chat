import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_client_provider.dart';
import '../settings/app_preferences_provider.dart';
import 'account_security_status.dart';
import 'confirmed_identity_store.dart';
import 'recovery_code.dart';
import 'user_trust.dart';

final recoveryWordlistProvider = FutureProvider<RecoveryWordlist>((ref) {
  return RecoveryWordlist.load();
});

final confirmedIdentityStoreProvider = Provider<ConfirmedIdentityStore>((ref) {
  return ConfirmedIdentityStore(ref.watch(sharedPreferencesProvider));
});

final accountSecurityFactsProvider = StreamProvider<AccountSecurityFacts>((
  ref,
) async* {
  final client = ref.watch(matrixClientProvider);
  yield await accountSecurityFactsOf(client);
  await for (final _ in client.onSync.stream) {
    yield await accountSecurityFactsOf(client);
  }
});

final accountSecurityStatusProvider =
    Provider<AsyncValue<AccountSecurityStatus>>(
      (ref) => ref
          .watch(accountSecurityFactsProvider)
          .whenData(accountSecurityStatus),
    );

final userTrustProvider = Provider.family<UserTrustState, String>((
  ref,
  userId,
) {
  final client = ref.watch(matrixClientProvider);
  ref.watch(accountSecurityFactsProvider);
  final facts = userTrustFactsOf(client.userDeviceKeys[userId]);
  return userTrustState(
    currentIdentityKey: facts.currentIdentityKey,
    identityDirectlyVerified: facts.identityDirectlyVerified,
    hasUnsignedDevices: facts.hasUnsignedDevices,
    confirmedIdentityKey: ref
        .watch(confirmedIdentityStoreProvider)
        .confirmedIdentityKey(userId),
  );
});

Future<void> rememberConfirmedIdentity(
  ConfirmedIdentityStore store,
  Client client,
  String userId,
) async {
  final key = client.userDeviceKeys[userId]?.masterKey?.ed25519Key;
  if (key == null) return;
  await store.remember(userId, key);
}

RecoveryWordlist? maybeWordlist(WidgetRef ref) =>
    ref.watch(recoveryWordlistProvider).value;
