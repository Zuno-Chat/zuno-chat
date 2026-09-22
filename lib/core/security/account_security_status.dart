import 'package:matrix/matrix.dart';

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
  return AccountSecurityFacts(
    recoveryExists: encryption.crossSigning.enabled,
    thisDeviceHasIdentityKeys: await encryption.crossSigning.isCached(),
    keyBackupExists: encryption.keyManager.enabled,
    keyBackupUsableHere: await encryption.keyManager.isCached(),
    unapprovedOtherDevices: ownKeys
        .where((d) => d.deviceId != client.deviceID && !d.verified)
        .length,
  );
}

({String title, String body, String? action}) accountSecurityCopy(
  AccountSecurityStatus status,
) {
  switch (status) {
    case AccountSecurityStatus.protected:
      return (
        title: 'Your messages are protected',
        body:
            'You can get them back on a new device, and your other devices are '
            'approved.',
        action: null,
      );
    case AccountSecurityStatus.noRecovery:
      return (
        title: 'If you lose this device, your messages go with it',
        body: 'Set up a recovery code so you can read them again on a new device.',
        action: 'Set up recovery',
      );
    case AccountSecurityStatus.deviceLocked:
      return (
        title: 'Older messages are not on this device yet',
        body: 'Approve this device from another one, or enter your recovery code.',
        action: 'Unlock them',
      );
    case AccountSecurityStatus.deviceWaiting:
      return (
        title: 'A new sign-in is waiting for approval',
        body: 'Check it is you, then approve it.',
        action: 'Review',
      );
    case AccountSecurityStatus.recoveryStale:
      return (
        title: 'This device has an old recovery code',
        body: "Enter the current one so it can read your backed-up messages.",
        action: 'Enter code',
      );
  }
}
