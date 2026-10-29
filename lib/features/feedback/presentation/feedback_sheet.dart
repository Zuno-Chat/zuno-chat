import 'package:flutter/material.dart';

import '../../../core/errors/feedback.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/ui/form_sheet.dart';

typedef SendFeedback = Future<void> Function(String message);

Future<void> showFeedbackSheet(
  BuildContext context, {
  SendFeedback onSend = sendFeedback,
}) {
  final l10n = context.l10n;
  return showFormSheet(
    context,
    sent: l10n.feedbackSent,
    builder: (_) => FormSheet(
      title: l10n.feedbackSheetTitle,
      explanation: l10n.feedbackExplanation,
      fieldLabel: l10n.feedbackLabel,
      minLines: 3,
      maxLines: 8,
      maxLength: 2000,
      autofocus: true,
      sendLabel: l10n.feedbackSheetTitle,
      failed: l10n.feedbackNotSent,
      debugLabel: 'send feedback',
      canSend: (text) => text.trim().isNotEmpty,
      send: onSend,
    ),
  );
}
