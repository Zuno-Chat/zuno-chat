import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/undecryptable_reason.dart';

void main() {
  group('undecryptableReason', () {
    test('a backup this device has not opened is recoverable', () {
      expect(
        undecryptableReason(keyBackupExists: true, keyBackupUsableHere: false),
        UndecryptableReason.recoverable,
      );
    });

    test('no backup at all means nothing can be done', () {
      expect(
        undecryptableReason(keyBackupExists: false, keyBackupUsableHere: false),
        UndecryptableReason.keyNeverShared,
      );
    });

    test('a backup already usable here cannot be the explanation', () {
      expect(
        undecryptableReason(keyBackupExists: true, keyBackupUsableHere: true),
        UndecryptableReason.keyNeverShared,
      );
    });
  });

  group('undecryptableCopy', () {
    test('only the recoverable case offers an action', () {
      expect(
        undecryptableCopy(UndecryptableReason.recoverable).offersRecovery,
        isTrue,
      );
      expect(
        undecryptableCopy(UndecryptableReason.keyNeverShared).offersRecovery,
        isFalse,
      );
    });

    test('neither line says "decrypt"', () {
      for (final reason in UndecryptableReason.values) {
        expect(
          undecryptableCopy(reason).text.toLowerCase(),
          isNot(contains('decrypt')),
          reason: reason.name,
        );
      }
    });
  });
}
