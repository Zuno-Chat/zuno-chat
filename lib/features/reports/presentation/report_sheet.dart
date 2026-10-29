import 'package:flutter/material.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/ui/form_sheet.dart';

typedef SendReport = Future<void> Function(ReportReason reason, String note);

Future<bool> showReportSheet(
  BuildContext context, {
  @displayText required String title,
  @displayText required String explanation,
  required SendReport onSend,
  @displayText String? sendLabel,
}) => showFormSheet(
  context,
  sent: context.l10n.commonReportSent,
  builder: (_) => _ReportSheet(
    title: title,
    explanation: explanation,
    sendLabel: sendLabel,
    onSend: onSend,
  ),
);

class _ReportSheet extends StatefulWidget {
  final String title;
  final String explanation;
  final String? sendLabel;
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
  ReportReason? _reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FormSheet(
      title: widget.title,
      explanation: widget.explanation,
      fieldLabel: _reason == ReportReason.other
          ? l10n.reportsWhatHappened
          : l10n.reportsWhatHappenedOptional,
      maxLines: 4,
      maxLength: 500,
      sendLabel: widget.sendLabel ?? l10n.reportsSend,
      failed: l10n.reportsNotSent,
      debugLabel: 'send abuse report',
      canSend: (note) => canSendReport(_reason, note),
      send: (note) => widget.onSend(_reason!, note),
      above: (context, sending) => RadioGroup<ReportReason>(
        groupValue: _reason,
        onChanged: (reason) {
          if (!sending) setState(() => _reason = reason);
        },
        child: Column(
          children: [
            for (final reason in ReportReason.values)
              RadioListTile<ReportReason>(
                title: Text(reason.label(l10n)),
                value: reason,
              ),
          ],
        ),
      ),
    );
  }
}
