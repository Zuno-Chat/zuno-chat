import 'package:matrix/matrix.dart';

enum ReportReason {
  spam('Spam'),
  harassment('Harassment'),
  illegal('Illegal content'),
  other('Something else');

  final String label;
  const ReportReason(this.label);
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
