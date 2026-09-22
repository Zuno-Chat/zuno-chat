import 'package:flutter/material.dart';

Future<bool> confirmSendingRecoveryCode(BuildContext context) async {
  final send = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Send your recovery code?'),
      content: const Text(
        'This message looks like your recovery code. Anyone who has it can '
        'read your messages on another device. Zuno never asks for it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Send anyway'),
        ),
      ],
    ),
  );
  return send ?? false;
}
