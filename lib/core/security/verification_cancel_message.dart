import '../l10n/l10n.dart';

class VerificationCancelMessage {
  final String title;
  final String body;
  final bool isAlarming;

  const VerificationCancelMessage({
    required this.title,
    required this.body,
    this.isAlarming = false,
  });
}

VerificationCancelMessage verificationCancelMessage(
  AppLocalizations l10n, {
  required String? code,
  required bool isOwnDevice,
}) {
  switch (code) {
    case 'm.user':
      return VerificationCancelMessage(
        title: l10n.securityCancelUserTitle,
        body: isOwnDevice
            ? l10n.securityCancelUserOwnBody
            : l10n.securityCancelUserOtherBody,
      );
    case 'm.timeout':
      return VerificationCancelMessage(
        title: l10n.securityCancelTimeoutTitle,
        body: l10n.securityCancelTimeoutBody,
      );
    case 'm.accepted':
      return VerificationCancelMessage(
        title: l10n.securityCancelAcceptedTitle,
        body: l10n.securityCancelAcceptedBody,
      );
    case 'm.key_mismatch':
    case 'm.mismatched_sas':
    case 'm.mismatched_commitment':
      return VerificationCancelMessage(
        title: l10n.securityCancelMismatchTitle,
        body: isOwnDevice
            ? l10n.securityCancelMismatchOwnBody
            : l10n.securityCancelMismatchOtherBody,
        isAlarming: true,
      );
    case 'm.user_mismatch':
      return VerificationCancelMessage(
        title: l10n.securityCancelUserMismatchTitle,
        body: l10n.securityCancelUserMismatchBody,
        isAlarming: true,
      );
    default:
      return VerificationCancelMessage(
        title: l10n.securityCancelDefaultTitle,
        body: l10n.securityCancelDefaultBody,
      );
  }
}
