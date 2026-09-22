import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/account_security_status.dart';

AccountSecurityFacts _facts({
  bool recoveryExists = true,
  bool thisDeviceHasIdentityKeys = true,
  bool keyBackupExists = true,
  bool keyBackupUsableHere = true,
  int unapprovedOtherDevices = 0,
}) => AccountSecurityFacts(
  recoveryExists: recoveryExists,
  thisDeviceHasIdentityKeys: thisDeviceHasIdentityKeys,
  keyBackupExists: keyBackupExists,
  keyBackupUsableHere: keyBackupUsableHere,
  unapprovedOtherDevices: unapprovedOtherDevices,
);

void main() {
  group('accountSecurityStatus', () {
    test('everything set up and nothing pending is protected', () {
      expect(accountSecurityStatus(_facts()), AccountSecurityStatus.protected);
    });

    test('no cross-signing identity at all is noRecovery', () {
      expect(
        accountSecurityStatus(
          _facts(
            recoveryExists: false,
            thisDeviceHasIdentityKeys: false,
            keyBackupExists: false,
            keyBackupUsableHere: false,
          ),
        ),
        AccountSecurityStatus.noRecovery,
      );
    });

    test(
      'identity exists but this device never unlocked it is deviceLocked',
      () {
        expect(
          accountSecurityStatus(_facts(thisDeviceHasIdentityKeys: false)),
          AccountSecurityStatus.deviceLocked,
        );
      },
    );

    test('an unapproved other device wins over everything else', () {
      expect(
        accountSecurityStatus(
          _facts(
            keyBackupUsableHere: false,
            unapprovedOtherDevices: 1,
          ),
        ),
        AccountSecurityStatus.deviceWaiting,
      );
    });

    test('a device that cannot check does not accuse the others', () {
      expect(
        accountSecurityStatus(
          _facts(
            thisDeviceHasIdentityKeys: false,
            unapprovedOtherDevices: 2,
          ),
        ),
        AccountSecurityStatus.deviceLocked,
      );
    });

    test('an unapproved device is ignored when there is no identity', () {
      expect(
        accountSecurityStatus(
          _facts(
            recoveryExists: false,
            thisDeviceHasIdentityKeys: false,
            keyBackupExists: false,
            keyBackupUsableHere: false,
            unapprovedOtherDevices: 3,
          ),
        ),
        AccountSecurityStatus.noRecovery,
      );
    });

    test('no recovery outranks an unapproved device that could be reviewed', () {
      expect(
        accountSecurityStatus(
          _facts(recoveryExists: false, unapprovedOtherDevices: 2),
        ),
        AccountSecurityStatus.noRecovery,
      );
    });

    test('no recovery outranks a backup this device cannot read', () {
      expect(
        accountSecurityStatus(
          _facts(recoveryExists: false, keyBackupUsableHere: false),
        ),
        AccountSecurityStatus.noRecovery,
      );
    });

    test('a backup this device cannot read is recoveryStale', () {
      expect(
        accountSecurityStatus(_facts(keyBackupUsableHere: false)),
        AccountSecurityStatus.recoveryStale,
      );
    });

    test('no backup at all does not count as stale', () {
      expect(
        accountSecurityStatus(
          _facts(keyBackupExists: false, keyBackupUsableHere: false),
        ),
        AccountSecurityStatus.protected,
      );
    });

    test('deviceLocked outranks recoveryStale', () {
      expect(
        accountSecurityStatus(
          _facts(thisDeviceHasIdentityKeys: false, keyBackupUsableHere: false),
        ),
        AccountSecurityStatus.deviceLocked,
      );
    });
  });

  group('accountSecurityCopy', () {
    test('every state has copy, and only protected has no action', () {
      for (final status in AccountSecurityStatus.values) {
        final copy = accountSecurityCopy(status);
        expect(copy.title, isNotEmpty, reason: status.name);
        expect(copy.body, isNotEmpty, reason: status.name);
        if (status == AccountSecurityStatus.protected) {
          expect(copy.action, isNull);
        } else {
          expect(copy.action, isNotNull, reason: status.name);
          expect(copy.action, isNotEmpty, reason: status.name);
        }
      }
    });

    test('no state mentions Matrix vocabulary', () {
      const banned = [
        'cross-signing',
        'session',
        'secret storage',
        'megolm',
        'fingerprint',
        'bootstrap',
        'cross signing',
      ];
      for (final status in AccountSecurityStatus.values) {
        final copy = accountSecurityCopy(status);
        final text = '${copy.title} ${copy.body} ${copy.action ?? ''}'
            .toLowerCase();
        for (final word in banned) {
          expect(
            text.contains(word),
            isFalse,
            reason: '${status.name} says "$word"',
          );
        }
      }
    });
  });
}
