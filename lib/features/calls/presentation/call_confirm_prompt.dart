import '../../../core/security/user_trust.dart';

const callConfirmPromptDelay = Duration(seconds: 30);

bool callConfirmPromptWanted({
  required UserTrustState trust,
  required bool thisDeviceReady,
  required bool theirDeviceApproved,
  required bool declined,
  required bool talkedLongEnough,
}) {
  final needsConfirming =
      trust == UserTrustState.unconfirmed ||
      trust == UserTrustState.identityChanged;
  return needsConfirming &&
      thisDeviceReady &&
      theirDeviceApproved &&
      !declined &&
      talkedLongEnough;
}
