import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/security/account_security_status.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/security_facts.dart';

void main() {
  group('accountSecurityStatus', () {
    test('everything set up and nothing pending is protected', () {
      expect(
        accountSecurityStatus(securityFacts()),
        AccountSecurityStatus.protected,
      );
    });

    test('no cross-signing identity at all is noRecovery', () {
      expect(
        accountSecurityStatus(
          securityFacts(
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
          accountSecurityStatus(
            securityFacts(thisDeviceHasIdentityKeys: false),
          ),
          AccountSecurityStatus.deviceLocked,
        );
      },
    );

    test('an unapproved other device wins over everything else', () {
      expect(
        accountSecurityStatus(
          securityFacts(keyBackupUsableHere: false, unapprovedOtherDevices: 1),
        ),
        AccountSecurityStatus.deviceWaiting,
      );
    });

    test('a device that cannot check does not accuse the others', () {
      expect(
        accountSecurityStatus(
          securityFacts(
            thisDeviceHasIdentityKeys: false,
            unapprovedOtherDevices: 2,
          ),
        ),
        AccountSecurityStatus.deviceLocked,
      );
    });

    test(
      'no recovery outranks an unapproved device that could be reviewed',
      () {
        expect(
          accountSecurityStatus(
            securityFacts(recoveryExists: false, unapprovedOtherDevices: 2),
          ),
          AccountSecurityStatus.noRecovery,
        );
      },
    );

    test('no recovery outranks a backup this device cannot read', () {
      expect(
        accountSecurityStatus(
          securityFacts(recoveryExists: false, keyBackupUsableHere: false),
        ),
        AccountSecurityStatus.noRecovery,
      );
    });

    test('a backup this device cannot read is recoveryStale', () {
      expect(
        accountSecurityStatus(securityFacts(keyBackupUsableHere: false)),
        AccountSecurityStatus.recoveryStale,
      );
    });

    test('no backup at all does not count as stale', () {
      expect(
        accountSecurityStatus(
          securityFacts(keyBackupExists: false, keyBackupUsableHere: false),
        ),
        AccountSecurityStatus.protected,
      );
    });

    test('deviceLocked outranks recoveryStale', () {
      expect(
        accountSecurityStatus(
          securityFacts(
            thisDeviceHasIdentityKeys: false,
            keyBackupUsableHere: false,
          ),
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

  group('accountSecurityFactsOf', () {
    const me = '@me:example.org';
    late EncryptedTestClient client;

    setUp(() {
      client = EncryptedTestClient(userId: me, testDeviceId: 'THIS');
    });

    test('a client without encryption has nothing set up', () async {
      final facts = await accountSecurityFactsOf(buildTestClient());

      expect(facts.recoveryExists, isFalse);
      expect(facts.thisDeviceHasIdentityKeys, isFalse);
      expect(facts.keyBackupExists, isFalse);
      expect(facts.keyBackupUsableHere, isFalse);
      expect(facts.unapprovedOtherDevices, 0);
    });

    test('no recovery on the server reads as none set up', () async {
      final facts = await accountSecurityFactsOf(client);

      expect(facts.recoveryExists, isFalse);
      expect(facts.keyBackupExists, isFalse);
      expect(accountSecurityStatus(facts), AccountSecurityStatus.noRecovery);
    });

    test('recovery this device has not unlocked reads as locked', () async {
      client.setUpRecovery();

      final facts = await accountSecurityFactsOf(client);

      expect(facts.recoveryExists, isTrue);
      expect(facts.thisDeviceHasIdentityKeys, isFalse);
      expect(facts.keyBackupExists, isTrue);
      expect(facts.keyBackupUsableHere, isFalse);
      expect(accountSecurityStatus(facts), AccountSecurityStatus.deviceLocked);
    });

    test('counts other devices not yet approved, never this one', () async {
      setTestDevices(client, me, {
        'THIS': null,
        'LAPTOP': null,
        'TABLET': null,
      });

      final facts = await accountSecurityFactsOf(client);

      expect(facts.unapprovedOtherDevices, 2);
    });

    test('no device list yet means nothing is waiting', () async {
      final facts = await accountSecurityFactsOf(client);

      expect(facts.unapprovedOtherDevices, 0);
    });

    test('checks identity keys and backup at the same time', () async {
      client.setUpRecovery();
      final db = client.encryptionDatabase;
      final identityKeys = Completer<Null>();
      db.heldSecretCacheReads[EventTypes.CrossSigningSelfSigning] =
          identityKeys;

      final facts = accountSecurityFactsOf(client);
      await pumpEventQueue();

      expect(db.secretCacheReads, contains(EventTypes.MegolmBackup));
      identityKeys.complete();
      expect((await facts).thisDeviceHasIdentityKeys, isFalse);
    });
  });
}
