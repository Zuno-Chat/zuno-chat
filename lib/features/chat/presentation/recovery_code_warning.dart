import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/ui/confirm_dialog.dart';

Future<bool> confirmSendingRecoveryCode(BuildContext context) {
  final l10n = context.l10n;
  return confirm(
    context,
    title: l10n.chatRecoveryCodeTitle,
    body: l10n.chatRecoveryCodeBody,
    confirmLabel: l10n.chatSendAnyway,
    tone: ConfirmTone.destructive,
  );
}
