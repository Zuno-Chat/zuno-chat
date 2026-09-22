import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'server_name.dart';
import 'username_field.dart';

Future<String?> showLocalUsernameDialog(
  BuildContext context, {
  required Client client,
  required String title,
  required String actionLabel,
}) async {
  final username = await showDialog<String>(
    context: context,
    builder: (context) =>
        _LocalUsernameDialog(title: title, actionLabel: actionLabel),
  );
  if (username == null || username.isEmpty) return null;
  return '@$username:${ownServerName(client)!}';
}

class _LocalUsernameDialog extends StatefulWidget {
  final String title;
  final String actionLabel;

  const _LocalUsernameDialog({required this.title, required this.actionLabel});

  @override
  State<_LocalUsernameDialog> createState() => _LocalUsernameDialogState();
}

class _LocalUsernameDialogState extends State<_LocalUsernameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        autofillHints: null,
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        inputFormatters: [lowercaseFormatter, usernameCharsFormatter],
        decoration: const InputDecoration(
          prefixText: '@',
          border: OutlineInputBorder(),
          hintText: 'username',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
