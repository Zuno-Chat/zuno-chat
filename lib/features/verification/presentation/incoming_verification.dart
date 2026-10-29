import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/security/verification_cancel_message.dart';
import '../../../core/ui/notice.dart';
import 'verification_page.dart';
import 'verification_request_dialog.dart';

Future<void> answerIncomingVerification(
  BuildContext context,
  KeyVerification request, {
  required bool isOwnDevice,
}) async {
  if (request.isDone) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final l10n = context.l10n;
  final accept = await showDialog<bool>(
    context: context,
    builder: (_) => VerificationRequestDialog(keyVerification: request),
  );
  if (request.isDone) {
    final message = verificationCancelMessage(
      l10n,
      code: request.canceledCode,
      isOwnDevice: isOwnDevice,
    );
    messenger.say(message.body);
    return;
  }
  if (!context.mounted) return;
  final accepted = accept == true;
  final answered = await attempt(
    context,
    accepted ? request.acceptVerification : request.rejectVerification,
    label: 'answer verification',
    failed: l10n.verificationCouldNotSend,
  );
  if (!answered || !accepted || !navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) =>
          VerificationPage(keyVerification: request, isOwnDevice: isOwnDevice),
    ),
  );
}
