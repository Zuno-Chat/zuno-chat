import 'package:flutter/material.dart';

import '../l10n/display_text.dart';
import '../l10n/l10n.dart';

enum ConfirmTone { plain, primary, destructive }

Future<bool> confirm(
  BuildContext context, {
  @displayText required String title,
  @displayText String? body,
  Widget? content,
  @displayText required String confirmLabel,
  @displayText String? cancelLabel,
  ConfirmTone tone = ConfirmTone.plain,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      void answer(bool value) => Navigator.of(context).pop(value);
      return AlertDialog(
        title: Text(title),
        content: content ?? (body == null ? null : Text(body)),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
            onPressed: () => answer(false),
            child: Text(cancelLabel ?? context.l10n.commonCancel),
          ),
          switch (tone) {
            ConfirmTone.primary => FilledButton(
              onPressed: () => answer(true),
              child: Text(confirmLabel),
            ),
            ConfirmTone.plain || ConfirmTone.destructive => TextButton(
              onPressed: () => answer(true),
              style: tone == ConfirmTone.destructive
                  ? destructiveButtonStyle(context)
                  : null,
              child: Text(confirmLabel),
            ),
          },
        ],
      );
    },
  );
  return confirmed ?? false;
}

ButtonStyle destructiveButtonStyle(BuildContext context) =>
    TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error);
