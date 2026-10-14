import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';

final _passwordSent = Expando<bool>('uia password sent');
final _asking = Expando<bool>('uia password asked');

Future<String?> askPasswordForUia(
  BuildContext context, {
  @displayText String? title,
  @displayText String? message,
  @displayText String? error,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final l10n = context.l10n;
      final field = AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: l10n.commonPassword,
            errorText: error,
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
      );
      return AlertDialog(
        title: Text(title ?? l10n.settingsUiaDefaultTitle),
        content: message == null
            ? field
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(message), const SizedBox(height: 16), field],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.settingsUiaConfirm),
          ),
        ],
      );
    },
  );
}

Future<void> answerUiaWithPassword(
  BuildContext context,
  UiaRequest uia, {
  required String userId,
  @displayText String? title,
  @displayText String? message,
  String? Function()? preparedPassword,
}) async {
  if (uia.state != UiaRequestState.waitForUser || _asking[uia] == true) return;
  if (!uia.nextStages.contains(AuthenticationTypes.password)) {
    uia.cancel();
    return;
  }
  _asking[uia] = true;
  final String? password;
  try {
    password =
        preparedPassword?.call() ??
        await askPasswordForUia(
          context,
          title: title,
          message: message,
          error: _passwordSent[uia] == true
              ? context.l10n.commonWrongPassword
              : null,
        );
  } finally {
    _asking[uia] = false;
  }
  if (!context.mounted || password == null || password.isEmpty) {
    uia.cancel();
    return;
  }
  _passwordSent[uia] = true;
  await uia.completeStage(
    AuthenticationPassword(
      session: uia.session,
      password: password,
      identifier: AuthenticationUserIdentifier(user: userId),
    ),
  );
}
