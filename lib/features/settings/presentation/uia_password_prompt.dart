import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

final _passwordSent = Expando<bool>('uia password sent');
final _asking = Expando<bool>('uia password asked');

Future<String?> askPasswordForUia(
  BuildContext context, {
  String title = 'Confirm your password',
  String? error,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(labelText: 'Password', errorText: error),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

Future<void> answerUiaWithPassword(
  BuildContext context,
  UiaRequest uia, {
  required String userId,
  String title = 'Confirm your password',
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
          error: _passwordSent[uia] == true ? 'Wrong password.' : null,
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
