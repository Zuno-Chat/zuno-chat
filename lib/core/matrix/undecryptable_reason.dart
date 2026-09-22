enum UndecryptableReason { recoverable, keyNeverShared }

UndecryptableReason undecryptableReason({
  required bool keyBackupExists,
  required bool keyBackupUsableHere,
}) => keyBackupExists && !keyBackupUsableHere
    ? UndecryptableReason.recoverable
    : UndecryptableReason.keyNeverShared;

({String text, bool offersRecovery}) undecryptableCopy(
  UndecryptableReason reason,
) => switch (reason) {
  UndecryptableReason.recoverable => (
    text: 'Sent before this device signed in.',
    offersRecovery: true,
  ),
  UndecryptableReason.keyNeverShared => (
    text: "The sender's device did not share the key for this message.",
    offersRecovery: false,
  ),
};
