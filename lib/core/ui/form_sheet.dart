import 'package:flutter/material.dart';

import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import '../l10n/display_text.dart';
import '../l10n/l10n.dart';
import '../security/zuno_text_field.dart';
import 'notice.dart';
import 'sheet.dart';

Future<bool> showFormSheet(
  BuildContext context, {
  @displayText required String sent,
  required WidgetBuilder builder,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final done = await showSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: builder,
  );
  if (done != true) return false;
  messenger.say(sent);
  return true;
}

class FormSheet extends StatefulWidget {
  final String title;
  final String explanation;
  final String fieldLabel;
  final int minLines;
  final int maxLines;
  final int maxLength;
  final bool autofocus;
  final String sendLabel;
  final String failed;
  final String debugLabel;
  final bool Function(String text) canSend;
  final Future<void> Function(String text) send;
  final Widget Function(BuildContext context, bool sending)? above;

  const FormSheet({
    @displayText required this.title,
    @displayText required this.explanation,
    @displayText required this.fieldLabel,
    required this.maxLines,
    required this.maxLength,
    @displayText required this.sendLabel,
    @displayText required this.failed,
    required this.debugLabel,
    required this.canSend,
    required this.send,
    this.minLines = 1,
    this.autofocus = false,
    this.above,
    super.key,
  });

  @override
  State<FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<FormSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  Object? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.send(_text.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, s) {
      reportCaught(widget.debugLabel, e, s);
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final above = widget.above;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(widget.title, style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  widget.explanation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ?above?.call(context, _sending),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: ZunoTextField(
                  autofillHints: null,
                  controller: _text,
                  enabled: !_sending,
                  autofocus: widget.autofocus,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  maxLength: widget.maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: widget.fieldLabel,
                    alignLabelWithHint: true,
                    errorText: _error == null
                        ? null
                        : failureMessage(
                            context.l10n,
                            _error,
                            failed: widget.failed,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ListenableBuilder(
                  listenable: _text,
                  builder: (context, _) => FilledButton(
                    onPressed: !_sending && widget.canSend(_text.text)
                        ? _send
                        : null,
                    child: Text(widget.sendLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
