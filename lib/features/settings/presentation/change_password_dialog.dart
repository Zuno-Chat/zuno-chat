import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;

import '../../../core/security/password_strength.dart';

class ChangePasswordDialog extends StatefulWidget {
  final String username;
  final Future<void> Function(String current, String next) onSubmit;

  const ChangePasswordDialog({
    super.key,
    required this.username,
    required this.onSubmit,
  });

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  late final _username = TextEditingController(text: widget.username);
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _inputError() {
    if (_current.text.isEmpty || _next.text.isEmpty) {
      return 'Fill in both password fields';
    }
    if (_next.text != _confirm.text) return 'New passwords do not match';
    return assessPassword(_next.text, username: widget.username).blocker;
  }

  Future<void> _submit() async {
    if (_loading) return;
    final inputError = _inputError();
    if (inputError != null) {
      setState(() => _error = inputError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_current.text, _next.text);
      TextInput.finishAutofillContext();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Password not changed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: const Text('Change password'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 4,
      content: SizedBox(
        width: double.maxFinite,
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _username,
                readOnly: true,
                canRequestFocus: false,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              gap,
              TextField(
                controller: _current,
                enabled: !_loading,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              gap,
              TextField(
                controller: _next,
                enabled: !_loading,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              gap,
              TextField(
                controller: _confirm,
                enabled: !_loading,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: Text(_loading ? 'Changing password…' : 'Change password'),
        ),
      ],
    );
  }
}
