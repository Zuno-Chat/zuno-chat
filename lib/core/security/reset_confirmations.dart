import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import 'confirmed_identity_store.dart';

Future<void> forgetConfirmationsAfterIdentityReset(
  Client client,
  ConfirmedIdentityStore store,
) async {
  await runBestEffort(
    store.forgetAll,
    label: 'forget confirmed identities after a reset',
  );

  final ownId = client.userID;
  for (final list in List.of(client.userDeviceKeys.values)) {
    if (list.userId == ownId) continue;
    final master = list.masterKey;
    if (master == null || !master.directVerified) continue;
    await runBestEffort(
      () => master.setVerified(false, false),
      label: 'unverify an identity after a reset',
    );
  }
}
