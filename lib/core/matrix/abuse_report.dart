import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';

enum ReportReason {
  spam,
  harassment,
  illegal,
  other;

  String label(AppLocalizations l10n) => switch (this) {
    spam => l10n.matrixReportReasonSpam,
    harassment => l10n.matrixReportReasonHarassment,
    illegal => l10n.matrixReportReasonIllegal,
    other => l10n.matrixReportReasonOther,
  };
}

bool canSendReport(ReportReason? reason, String note) {
  if (reason == null) return false;
  return reason != ReportReason.other || note.trim().isNotEmpty;
}

String reportReasonText(
  ReportReason reason, {
  String note = '',
  String? roomId,
}) {
  final trimmed = note.trim();
  return [
    if (trimmed.isEmpty) reason.name else '${reason.name}: $trimmed',
    if (roomId != null) '(room $roomId)',
  ].join(' ');
}

Future<void> reportMessage(
  Event event,
  ReportReason reason, {
  String note = '',
}) {
  return event.room.client.reportEvent(
    event.room.id,
    event.eventId,
    reason: reportReasonText(reason, note: note),
  );
}

Future<void> reportPerson(
  Client client,
  String userId,
  ReportReason reason, {
  String note = '',
  String? roomId,
}) {
  return client.reportUser(
    userId,
    reportReasonText(reason, note: note, roomId: roomId),
  );
}
