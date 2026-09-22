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

bool _isProtocolToken(String? text) {
  final trimmed = text?.trim() ?? '';
  return trimmed.isEmpty || trimmed.startsWith('m.');
}

VerificationCancelMessage verificationCancelMessage({
  required String? code,
  required String? reason,
  required bool isOwnDevice,
}) {
  switch (code) {
    case 'm.user':
      return VerificationCancelMessage(
        title: 'Canceled',
        body: isOwnDevice
            ? 'The check was canceled on one of the two devices. Nothing '
                  'changed. Start it again whenever you like.'
            : 'One of you canceled the check. Nothing changed. Start it again '
                  'whenever you like.',
      );
    case 'm.timeout':
      return const VerificationCancelMessage(
        title: 'Timed out',
        body:
            'Nobody answered in time, so the check stopped on its own. '
            'Nothing changed.',
      );
    case 'm.accepted':
      return const VerificationCancelMessage(
        title: 'Answered somewhere else',
        body:
            'Another one of your devices picked this up first. Nothing '
            'to do here.',
      );
    case 'm.key_mismatch':
    case 'm.mismatched_sas':
    case 'm.mismatched_commitment':
      return VerificationCancelMessage(
        title: 'The codes did not match',
        isAlarming: true,
        body: isOwnDevice
            ? 'The two screens showed different codes, so this device was not '
                  'approved. Try again on a network you trust. If it keeps '
                  'happening, sign that device out.'
            : 'The two screens showed different codes, so they were not '
                  'confirmed. Try again in person if you can. If it keeps '
                  'happening, treat this chat as unconfirmed.',
      );
    case 'm.user_mismatch':
      return const VerificationCancelMessage(
        title: 'That was someone else',
        isAlarming: true,
        body:
            "The check was answered by a different account than the one "
            'it was started with. Nothing was confirmed.',
      );
    default:
      return VerificationCancelMessage(
        title: 'That did not finish',
        body: _isProtocolToken(reason)
            ? 'The two devices stopped agreeing partway through. Nothing '
                  'changed. Starting again usually fixes it.'
            : reason!.trim(),
      );
  }
}
