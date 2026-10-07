import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/format/chat_list_time.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/official_room.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/matrix/typing_indicator_text.dart';

@immutable
class ChatRowData {
  final String roomId;
  final String title;
  final Uri? avatarUrl;
  final bool isDirect;
  final bool community;
  final String toneSeed;
  final String? lastEventId;
  final EventStatus? lastEventStatus;
  final MessageKind? previewKind;
  final String? previewText;
  final String? previewSource;
  final String? typingText;
  final String timeLabel;
  final int unread;
  final bool muted;
  final bool encrypted;
  final bool awaitingAcceptance;
  final String? pendingInviteSubtitle;
  final bool partnerLeft;
  final bool official;

  const ChatRowData({
    required this.roomId,
    required this.title,
    required this.avatarUrl,
    required this.isDirect,
    this.community = false,
    required this.toneSeed,
    required this.lastEventId,
    required this.lastEventStatus,
    required this.previewKind,
    required this.previewText,
    this.previewSource,
    required this.typingText,
    required this.timeLabel,
    required this.unread,
    required this.muted,
    required this.encrypted,
    required this.awaitingAcceptance,
    required this.pendingInviteSubtitle,
    required this.partnerLeft,
    required this.official,
  });

  static const prototype = ChatRowData(
    roomId: '',
    title: 'Name',
    avatarUrl: null,
    isDirect: true,
    toneSeed: '',
    lastEventId: null,
    lastEventStatus: null,
    previewKind: MessageKind.text,
    previewText: 'Preview',
    typingText: null,
    timeLabel: '00:00',
    unread: 1,
    muted: false,
    encrypted: true,
    awaitingAcceptance: false,
    pendingInviteSubtitle: null,
    partnerLeft: false,
    official: false,
  );

  bool get dimmed => muted || awaitingAcceptance || partnerLeft;

  List<Object?> get _fields => [
    roomId,
    title,
    avatarUrl,
    isDirect,
    community,
    toneSeed,
    lastEventId,
    lastEventStatus,
    previewKind,
    previewText,
    previewSource,
    typingText,
    timeLabel,
    unread,
    muted,
    encrypted,
    awaitingAcceptance,
    pendingInviteSubtitle,
    partnerLeft,
    official,
  ];

  @override
  bool operator ==(Object other) =>
      other is ChatRowData && listEquals(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);
}

ChatRowData chatRowDataFor(
  Room room, {
  required Map<String, int> unreadCorrections,
  required DateTime now,
  required bool use24Hour,
}) {
  final display = roomInviteDisplay(room);
  final event = room.lastEvent;
  final summary = event != null && isPreviewableLastEvent(event)
      ? summarize(event)
      : null;
  final typing = typingIndicatorText(
    room.typingUsers.where((user) => user.id != room.client.userID).toList(),
  );

  return ChatRowData(
    roomId: room.id,
    title: display.title,
    avatarUrl: display.avatarUrl,
    isDirect: room.isDirectChat,
    toneSeed: roomToneSeed(room),
    lastEventId: event?.eventId,
    lastEventStatus: event?.status,
    previewKind: summary?.kind,
    previewText: summary?.text,
    typingText: typing,
    timeLabel: event == null || display.awaitingAcceptance
        ? ''
        : chatListTimeLabel(
            event.originServerTs,
            now: now,
            use24Hour: use24Hour,
          ),
    unread: displayedUnreadCount(unreadCorrections, room),
    muted: room.pushRuleState == PushRuleState.dontNotify,
    encrypted: room.encrypted,
    awaitingAcceptance: display.awaitingAcceptance,
    pendingInviteSubtitle: display.awaitingAcceptance
        ? pendingInviteSubtitle(room)
        : null,
    partnerLeft: display.partnerLeft,
    official: isOfficialZunoRoom(room),
  );
}

ChatRowData communityRowDataFor(
  Room community,
  List<Room> rooms, {
  required Map<String, int> unreadCorrections,
  required DateTime now,
  required bool use24Hour,
}) {
  final newest = rooms.firstOrNull;
  final event = newest?.lastEvent;
  final summary = event != null && isPreviewableLastEvent(event)
      ? summarize(event)
      : null;
  var unread = 0;
  for (final room in rooms) {
    if (room.pushRuleState == PushRuleState.dontNotify) continue;
    unread += displayedUnreadCount(unreadCorrections, room);
  }

  return ChatRowData(
    roomId: community.id,
    title: roomTitle(community),
    avatarUrl: community.avatar,
    isDirect: false,
    community: true,
    toneSeed: community.id,
    lastEventId: event?.eventId,
    lastEventStatus: event?.status,
    previewKind: summary?.kind,
    previewText: summary?.text,
    previewSource: newest == null ? null : roomTitle(newest),
    typingText: null,
    timeLabel: event == null
        ? ''
        : chatListTimeLabel(
            event.originServerTs,
            now: now,
            use24Hour: use24Hour,
          ),
    unread: unread,
    muted: false,
    encrypted: true,
    awaitingAcceptance: false,
    pendingInviteSubtitle: null,
    partnerLeft: false,
    official: false,
  );
}
