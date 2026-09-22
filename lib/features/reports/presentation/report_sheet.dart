import 'package:flutter/material.dart';

import '../../../core/matrix/abuse_report.dart';

typedef SendReport = Future<void> Function(ReportReason reason, String note);

Future<bool> showReportSheet(
  BuildContext context, {
  required String title,
  required String explanation,
  required SendReport onSend,
  String sendLabel = 'Send report',
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(
      title: title,
      explanation: explanation,
      sendLabel: sendLabel,
      onSend: onSend,
    ),
  );
  return sent ?? false;
}

class _ReportSheet extends StatefulWidget {
  final String title;
  final String explanation;
  final String sendLabel;
  final SendReport onSend;

  const _ReportSheet({
    required this.title,
    required this.explanation,
    required this.sendLabel,
    required this.onSend,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.onSend(reason, _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = !_sending && canSendReport(_reason, _note.text);

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
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (reason) {
                  if (!_sending) setState(() => _reason = reason);
                },
                child: Column(
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        title: Text(reason.label),
                        value: reason,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: TextField(
                  autofillHints: null,
                  controller: _note,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _reason == ReportReason.other
                        ? 'What happened'
                        : 'What happened (optional)',
                    errorText: _failed
                        ? 'The report was not sent. Try again.'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: FilledButton(
                  onPressed: canSend ? _send : null,
                  child: Text(widget.sendLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
