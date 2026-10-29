import 'package:flutter/material.dart';

import '../l10n/display_text.dart';
import '../l10n/l10n.dart';
import '../security/zuno_text_field.dart';

Future<String?> showEditTextDialog(
  BuildContext context, {
  @displayText required String title,
  required String initialValue,
  String? prefixText,
  int maxLines = 1,
  int? maxLength,
  bool allowEmpty = true,
  String? Function(String value)? validator,
}) => showDialog<String>(
  context: context,
  builder: (_) => _EditTextDialog(
    title: title,
    initialValue: initialValue,
    prefixText: prefixText,
    maxLines: maxLines,
    maxLength: maxLength,
    allowEmpty: allowEmpty,
    validator: validator,
  ),
);

class _EditTextDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String? prefixText;
  final int maxLines;
  final int? maxLength;
  final bool allowEmpty;
  final String? Function(String value)? validator;

  const _EditTextDialog({
    required this.title,
    required this.initialValue,
    required this.prefixText,
    required this.maxLines,
    required this.maxLength,
    required this.allowEmpty,
    required this.validator,
  });

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty && !widget.allowEmpty) return;
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: ZunoTextField(
      autofillHints: null,
      controller: _controller,
      autofocus: true,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(
        labelText: widget.title,
        prefixText: widget.prefixText,
        errorText: _error,
      ),
      onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.commonCancel),
      ),
      FilledButton(onPressed: _submit, child: Text(context.l10n.commonSave)),
    ],
  );
}
