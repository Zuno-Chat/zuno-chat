import 'package:matrix/matrix.dart';

import '../calls/matrixrtc/call_summary_message.dart';
import '../security/verification_signaling.dart';
import 'attachment_message_type.dart';
import 'image_caption.dart';
import 'reply_fallback.dart';
import 'state_event_description.dart';
import 'undecryptable_event.dart';
import 'voice_message.dart';

enum MessageKind {
  text,
  photo,
  video,
  voice,
  file,
  location,
  callSummary,
  deleted,
  undecryptable,
  nonMessage,
  hiddenSignaling,
}

class MessageSummary {
  final MessageKind kind;
  final String text;
  final CallSummary? call;

  const MessageSummary({required this.kind, required this.text, this.call});
}

bool isDisplayableTimelineEvent(
  Event event, {
  required bool showHiddenMessages,
}) {
  if (event.relationshipType == RelationshipTypes.edit) return false;

  final isRealMessage =
      event.type == EventTypes.Message ||
      event.type == EventTypes.Sticker ||
      isUndecryptableEvent(event);
  if (isRealMessage) {
    if (isVerificationSignalingMessage(event.messageType)) return false;
    return showHiddenMessages || !isCallSignalingMessage(event.messageType);
  }
  return showHiddenMessages && event.stateKey != null;
}

bool canCarryReadMarker(Event event) => event.status.isSent;

bool isPreviewableLastEvent(Event event) => isDisplayableTimelineEvent(
  _applyEdit(event) ?? event,
  showHiddenMessages: false,
);

MessageSummary summarize(Event event) {
  if (event.redacted) {
    return const MessageSummary(
      kind: MessageKind.deleted,
      text: 'Message deleted',
    );
  }
  if (isUndecryptableEvent(event)) {
    return const MessageSummary(
      kind: MessageKind.undecryptable,
      text: 'Message cannot be read on this device',
    );
  }

  final edited = _applyEdit(event);
  if (edited != null) return summarize(edited);

  if (event.type != EventTypes.Message && event.type != EventTypes.Sticker) {
    return MessageSummary(
      kind: MessageKind.nonMessage,
      text: describeStateEvent(event) ?? '${event.type} event',
    );
  }

  final msgtype = event.messageType;

  if (isCallSignalingMessage(msgtype) ||
      isVerificationSignalingMessage(msgtype)) {
    return MessageSummary(kind: MessageKind.hiddenSignaling, text: event.body);
  }

  final callSummary = CallSummary.fromEvent(event);
  if (callSummary != null) {
    return MessageSummary(
      kind: MessageKind.callSummary,
      text: callSummary.displayBody,
      call: callSummary,
    );
  }

  if (msgtype == MessageTypes.Image || msgtype == MessageTypes.Sticker) {
    return MessageSummary(
      kind: MessageKind.photo,
      text: imageCaption(event) ?? 'Photo',
    );
  }
  if (msgtype == MessageTypes.Video) {
    return MessageSummary(
      kind: MessageKind.video,
      text: imageCaption(event) ?? 'Video',
    );
  }
  if (isVoiceMessage(event)) {
    return const MessageSummary(kind: MessageKind.voice, text: 'Voice message');
  }
  if (isAttachmentMessageType(msgtype)) {
    return MessageSummary(kind: MessageKind.file, text: event.body);
  }
  if (msgtype == MessageTypes.Location) {
    return const MessageSummary(kind: MessageKind.location, text: 'Location');
  }

  return MessageSummary(
    kind: MessageKind.text,
    text: stripReplyFallback(event.plaintextBody),
  );
}

Event? _applyEdit(Event event) {
  if (event.relationshipType != RelationshipTypes.edit) return null;
  final newContent = event.content.tryGetMap<String, Object?>('m.new_content');
  if (newContent == null) return null;
  return Event(
    status: event.status,
    content: Map<String, dynamic>.from(newContent),
    type: event.type,
    eventId: event.eventId,
    senderId: event.senderId,
    originServerTs: event.originServerTs,
    stateKey: event.stateKey,
    room: event.room,
  );
}
