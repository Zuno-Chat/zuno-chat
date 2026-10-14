import 'package:matrix/matrix.dart';

import '../calls/matrixrtc/call_summary_message.dart';
import '../l10n/l10n.dart';
import '../location/live_location_protocol.dart';
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
  liveLocation,
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

MessageKind messageKindOf(Event event) => _classify(event).kind;

MessageSummary summarize(AppLocalizations l10n, Event event) {
  final (:kind, event: shown) = _classify(event);
  final call = kind == MessageKind.callSummary
      ? CallSummary.fromEvent(shown)
      : null;
  return MessageSummary(
    kind: kind,
    call: call,
    text: switch (kind) {
      MessageKind.deleted => l10n.matrixSummaryDeleted,
      MessageKind.undecryptable => l10n.matrixSummaryUndecryptable,
      MessageKind.nonMessage =>
        describeStateEvent(l10n, shown) ??
            l10n.matrixSummaryOtherEvent(shown.type),
      MessageKind.hiddenSignaling || MessageKind.file => shown.body,
      MessageKind.callSummary => call!.localizedBody(l10n),
      MessageKind.photo => imageCaption(shown) ?? l10n.matrixSummaryPhoto,
      MessageKind.video => imageCaption(shown) ?? l10n.matrixSummaryVideo,
      MessageKind.voice => l10n.matrixSummaryVoice,
      MessageKind.location => l10n.matrixSummaryLocation,
      MessageKind.liveLocation => l10n.matrixSummaryLiveLocation,
      MessageKind.text => stripReplyFallback(shown.plaintextBody),
    },
  );
}

({MessageKind kind, Event event}) _classify(Event event) {
  if (event.redacted) return (kind: MessageKind.deleted, event: event);
  if (isUndecryptableEvent(event)) {
    return (kind: MessageKind.undecryptable, event: event);
  }
  final edited = _applyEdit(event);
  if (edited != null) return _classify(edited);
  return (kind: _contentKind(event), event: event);
}

MessageKind _contentKind(Event event) {
  if (event.type != EventTypes.Message && event.type != EventTypes.Sticker) {
    return MessageKind.nonMessage;
  }
  final msgtype = event.messageType;
  if (isCallSignalingMessage(msgtype) ||
      isVerificationSignalingMessage(msgtype)) {
    return MessageKind.hiddenSignaling;
  }
  if (CallSummary.fromEvent(event) != null) return MessageKind.callSummary;
  if (msgtype == MessageTypes.Image || msgtype == MessageTypes.Sticker) {
    return MessageKind.photo;
  }
  if (msgtype == MessageTypes.Video) return MessageKind.video;
  if (isVoiceMessage(event)) return MessageKind.voice;
  if (isAttachmentMessageType(msgtype)) return MessageKind.file;
  if (msgtype == MessageTypes.Location) return MessageKind.location;
  if (msgtype == liveLocationMsgtype) return MessageKind.liveLocation;
  return MessageKind.text;
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
