import '../l10n/l10n.dart';

enum UndecryptableReason { recoverable, keyNeverShared }

UndecryptableReason undecryptableReason({
  required bool keyBackupExists,
  required bool keyBackupUsableHere,
}) => keyBackupExists && !keyBackupUsableHere
    ? UndecryptableReason.recoverable
    : UndecryptableReason.keyNeverShared;

({String text, bool offersRecovery}) undecryptableCopy(
  AppLocalizations l10n,
  UndecryptableReason reason,
) => switch (reason) {
  UndecryptableReason.recoverable => (
    text: l10n.matrixUndecryptableRecoverable,
    offersRecovery: true,
  ),
  UndecryptableReason.keyNeverShared => (
    text: l10n.matrixUndecryptableKeyNeverShared,
    offersRecovery: false,
  ),
};
