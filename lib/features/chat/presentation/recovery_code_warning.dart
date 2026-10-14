import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';

Future<bool> confirmSendingRecoveryCode(BuildContext context) async {
  final send = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.chatRecoveryCodeTitle),
      content: Text(context.l10n.chatRecoveryCodeBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(context.l10n.chatSendAnyway),
        ),
      ],
    ),
  );
  return send ?? false;
}
