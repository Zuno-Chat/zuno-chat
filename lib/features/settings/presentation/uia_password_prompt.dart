import 'package:flutter/material.dart';

Future<String?> askPasswordForUia(
  BuildContext context, {
  String title = 'Confirm your password',
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
          decoration: const InputDecoration(labelText: 'Password'),
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
