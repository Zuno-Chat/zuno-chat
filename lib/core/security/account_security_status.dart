import 'dart:async';

import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';

enum AccountSecurityStatus {
  deviceWaiting,
  deviceLocked,
  recoveryStale,
  noRecovery,
  protected,
}

class AccountSecurityFacts {
  final bool recoveryExists;
  final bool thisDeviceHasIdentityKeys;
  final bool keyBackupExists;
  final bool keyBackupUsableHere;
  final int unapprovedOtherDevices;

  const AccountSecurityFacts({
    required this.recoveryExists,
    required this.thisDeviceHasIdentityKeys,
    required this.keyBackupExists,
    required this.keyBackupUsableHere,
    required this.unapprovedOtherDevices,
  });
}

AccountSecurityStatus accountSecurityStatus(AccountSecurityFacts facts) {
  if (!facts.recoveryExists) return AccountSecurityStatus.noRecovery;
  if (!facts.thisDeviceHasIdentityKeys) {
    return AccountSecurityStatus.deviceLocked;
  }
  if (facts.unapprovedOtherDevices > 0) {
    return AccountSecurityStatus.deviceWaiting;
  }
  if (facts.keyBackupExists && !facts.keyBackupUsableHere) {
    return AccountSecurityStatus.recoveryStale;
  }
  return AccountSecurityStatus.protected;
}

Future<AccountSecurityFacts> accountSecurityFactsOf(Client client) async {
  final encryption = client.encryption;
  if (encryption == null) {
    return const AccountSecurityFacts(
      recoveryExists: false,
      thisDeviceHasIdentityKeys: false,
      keyBackupExists: false,
      keyBackupUsableHere: false,
      unapprovedOtherDevices: 0,
    );
  }
  final ownKeys = client.userDeviceKeys[client.userID]?.deviceKeys.values ?? [];
  final (identityKeysHere, keyBackupHere) = await (
    encryption.crossSigning.isCached(),
    encryption.keyManager.isCached(),
  ).wait;
  return AccountSecurityFacts(
    recoveryExists: encryption.crossSigning.enabled,
    thisDeviceHasIdentityKeys: identityKeysHere,
    keyBackupExists: encryption.keyManager.enabled,
    keyBackupUsableHere: keyBackupHere,
    unapprovedOtherDevices: ownKeys
        .where((d) => d.deviceId != client.deviceID && !d.verified)
        .length,
  );
}

({String title, String body, String? action}) accountSecurityCopy(
  AppLocalizations l10n,
  AccountSecurityStatus status,
) {
  switch (status) {
    case AccountSecurityStatus.protected:
      return (
        title: l10n.securityProtectedTitle,
        body: l10n.securityProtectedBody,
        action: null,
      );
    case AccountSecurityStatus.noRecovery:
      return (
        title: l10n.securityNoRecoveryTitle,
        body: l10n.securityNoRecoveryBody,
        action: l10n.securitySetUpRecovery,
      );
    case AccountSecurityStatus.deviceLocked:
      return (
        title: l10n.securityDeviceLockedTitle,
        body: l10n.securityDeviceLockedBody,
        action: l10n.securityDeviceLockedAction,
      );
    case AccountSecurityStatus.deviceWaiting:
      return (
        title: l10n.securityDeviceWaitingTitle,
        body: l10n.securityDeviceWaitingBody,
        action: l10n.commonReview,
      );
    case AccountSecurityStatus.recoveryStale:
      return (
        title: l10n.securityRecoveryStaleTitle,
        body: l10n.securityRecoveryStaleBody,
        action: l10n.securityRecoveryStaleAction,
      );
  }
}
