import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_summary_message.dart';

bool isNotSent(Event event) =>
    event.status.isError &&
    event.senderId == event.room.client.userID &&
    !isCallSignalingMessage(event.messageType) &&
    !isCallSummaryMessage(event.messageType);

Event? notSentBehind(Event event, Timeline timeline) {
  final drawnId = event.getDisplayEvent(timeline).eventId;
  final drawn = drawnId == event.eventId
      ? event
      : event
            .aggregatedEvents(timeline, RelationshipTypes.edit)
            .where((edit) => edit.eventId == drawnId)
            .firstOrNull;
  return drawn != null && isNotSent(drawn) ? drawn : null;
}

List<Event> notSentOwnEvents(Timeline timeline) => [
  for (final event in timeline.events)
    if (isNotSent(event) && !_isReplacedEdit(event, timeline)) event,
]..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));

bool _isReplacedEdit(Event event, Timeline timeline) {
  if (event.relationshipType != RelationshipTypes.edit) return false;
  final original = timeline.events
      .where((e) => e.eventId == event.relationshipEventId)
      .firstOrNull;
  return original != null &&
      original.getDisplayEvent(timeline).eventId != event.eventId;
}

Future<String?> resendUnsent(Event event) async {
  if (event.type == EventTypes.Message && !event.hasAttachment) {
    return event.sendAgain();
  }
  if (!event.status.isError) return null;
  return event.room.sendEvent(
    event.content,
    type: event.type,
    txid: event.transactionId ?? event.eventId,
  );
}
