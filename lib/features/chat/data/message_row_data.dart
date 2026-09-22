import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/chat_list_time.dart';
import '../../../core/matrix/reactions.dart';
import '../../../core/matrix/read_receipts.dart';
import '../../../core/matrix/undecryptable_event.dart';
import 'message_kinds.dart';
import 'message_look.dart';

@immutable
class MessageRowData {
  final String eventId;
  final EventStatus status;
  final String type;
  final String messageType;
  final bool redacted;
  final String displayEventId;
  final bool edited;
  final String timeLabel;
  final String? dayLabel;
  final bool isOwn;
  final bool isDirect;
  final String senderName;
  final Uri? senderAvatar;
  final bool startsRun;
  final bool endsRun;
  final String? replyToId;
  final String? replyDisplayEventId;
  final bool replyRedacted;
  final bool replyLoaded;
  final String? replyType;
  final String? replyMessageType;
  final String? replySenderName;
  final List<(String, int, bool)> reactions;
  final bool showReadTick;
  final bool isRead;
  final List<String> galleryIds;
  final List<EventStatus> galleryStatuses;
  final List<int> galleryFailureIndexes;
  final bool canReply;
  final bool linkPreviews;

  const MessageRowData({
    required this.eventId,
    required this.status,
    required this.type,
    required this.messageType,
    required this.redacted,
    required this.displayEventId,
    required this.edited,
    required this.timeLabel,
    required this.dayLabel,
    required this.isOwn,
    required this.isDirect,
    required this.senderName,
    required this.senderAvatar,
    required this.startsRun,
    required this.endsRun,
    required this.replyToId,
    required this.replyDisplayEventId,
    required this.replyRedacted,
    required this.replyLoaded,
    required this.replyType,
    required this.replyMessageType,
    required this.replySenderName,
    required this.reactions,
    required this.showReadTick,
    required this.isRead,
    required this.galleryIds,
    required this.galleryStatuses,
    required this.galleryFailureIndexes,
    required this.canReply,
    required this.linkPreviews,
  });

  MetaStatus get metaStatus {
    if (status.isSending) return MetaStatus.sending;
    if (!showReadTick) return MetaStatus.none;
    return isRead ? MetaStatus.read : MetaStatus.sent;
  }

  RunPosition get position =>
      RunPosition.of(startsRun: startsRun, endsRun: endsRun);

  List<Object?> get _fields => [
    eventId,
    status,
    type,
    messageType,
    redacted,
    displayEventId,
    edited,
    timeLabel,
    dayLabel,
    isOwn,
    isDirect,
    senderName,
    senderAvatar,
    startsRun,
    endsRun,
    replyToId,
    replyDisplayEventId,
    replyRedacted,
    replyLoaded,
    replyType,
    replyMessageType,
    replySenderName,
    showReadTick,
    isRead,
    canReply,
    linkPreviews,
    reactions.length,
    ...reactions,
    galleryIds.length,
    ...galleryIds,
    ...galleryStatuses,
    galleryFailureIndexes.length,
    ...galleryFailureIndexes,
  ];

  @override
  bool operator ==(Object other) =>
      other is MessageRowData && listEquals(_fields, other._fields);

  @override
  int get hashCode => Object.hashAll(_fields);
}

bool _startsRun(Event event, Event? older) {
  if (isHiddenTimelineEvent(event)) return false;
  if (older == null) return true;
  if (isHiddenTimelineEvent(older) || older.senderId != event.senderId) {
    return true;
  }
  if (!isSameLocalDay(event.originServerTs, older.originServerTs)) return true;
  return event.originServerTs.difference(older.originServerTs).abs() > runGap;
}

MessageRowData messageRowDataFor({
  required Event event,
  required Timeline timeline,
  required Map<String, Event> index,
  required Event? older,
  required Event? newer,
  required bool isLastOwn,
  required List<Event>? gallery,
  required List<int> galleryFailureIndexes,
  required bool canReply,
  required bool linkPreviews,
  required DateTime now,
  required bool use24Hour,
}) {
  final displayEvent = event.getDisplayEvent(timeline);
  final sender = event.senderFromMemoryOrFallback;
  final isOwn = event.senderId == event.room.client.userID;
  final showReadTick = isOwn && isLastOwn && event.status.isSent;
  final startsDay =
      older == null ||
      !isSameLocalDay(event.originServerTs, older.originServerTs);
  final replyToId = event.inReplyToEventId();
  final replyTarget = replyToId == null ? null : index[replyToId];
  final replyDisplay = replyTarget?.getDisplayEvent(timeline);
  final unreadable = event.redacted || isUndecryptableEvent(displayEvent);

  return MessageRowData(
    eventId: event.eventId,
    status: event.status,
    type: displayEvent.type,
    messageType: displayEvent.messageType,
    redacted: event.redacted,
    displayEventId: displayEvent.eventId,
    edited:
        !event.redacted &&
        event.hasAggregatedEvents(timeline, RelationshipTypes.edit),
    timeLabel: clockLabel(event.originServerTs.toLocal(), use24Hour),
    dayLabel: startsDay ? dateDividerLabel(event.originServerTs, now) : null,
    isOwn: isOwn,
    isDirect: event.room.isDirectChat,
    senderName: sender.calcDisplayname(),
    senderAvatar: sender.avatarUrl,
    startsRun: _startsRun(event, older),
    endsRun:
        newer == null ||
        isHiddenTimelineEvent(newer) ||
        _startsRun(newer, event),
    replyToId: replyToId,
    replyDisplayEventId: replyDisplay?.eventId,
    replyRedacted: replyTarget?.redacted ?? false,
    replyLoaded: replyTarget != null,
    replyType: replyDisplay?.type,
    replyMessageType: replyDisplay?.messageType,
    replySenderName: replyTarget?.senderFromMemoryOrFallback.calcDisplayname(),
    reactions: unreadable
        ? const []
        : [
            for (final reaction in reactionSummaries(event, timeline))
              (reaction.key, reaction.count, reaction.reactedByMe),
          ],
    showReadTick: showReadTick,
    isRead: showReadTick && isReadByOthers(event.room, event),
    galleryIds: [
      for (final member in gallery ?? const <Event>[]) member.eventId,
    ],
    galleryStatuses: [
      for (final member in gallery ?? const <Event>[]) member.status,
    ],
    galleryFailureIndexes: galleryFailureIndexes,
    canReply: canReply,
    linkPreviews: linkPreviews,
  );
}
