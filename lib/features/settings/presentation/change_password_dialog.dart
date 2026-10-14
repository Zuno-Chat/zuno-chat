import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;

import '../../../core/l10n/l10n.dart';
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
    final l10n = context.l10n;
    if (_current.text.isEmpty || _next.text.isEmpty) {
      return l10n.settingsChangePasswordFillBoth;
    }
    if (_next.text != _confirm.text) return l10n.settingsChangePasswordMismatch;
    return assessPassword(l10n, _next.text, username: widget.username).blocker;
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
        _error = context.l10n.settingsChangePasswordFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(l10n.settingsChangePasswordTitle),
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
                decoration: InputDecoration(labelText: l10n.commonUsername),
              ),
              gap,
              TextField(
                controller: _current,
                enabled: !_loading,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: l10n.settingsChangePasswordCurrent,
                ),
              ),
              gap,
              TextField(
                controller: _next,
                enabled: !_loading,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.settingsChangePasswordNew,
                ),
              ),
              gap,
              TextField(
                controller: _confirm,
                enabled: !_loading,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.settingsChangePasswordConfirm,
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
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: Text(
            _loading
                ? l10n.settingsChangePasswordChanging
                : l10n.settingsChangePasswordTitle,
          ),
        ),
      ],
    );
  }
}
