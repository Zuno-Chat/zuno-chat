import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/matrix/encryption/room_encryption.dart';
import '../../../core/matrix/events/event_display.dart';
import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/matrix/rooms/membership/room_invite.dart';
import '../../../core/matrix/rooms/official_room.dart';
import '../../../core/matrix/rooms/room_mute.dart';
import '../../../core/matrix/rooms/typing_indicator_text.dart';

@immutable
class ChatRowData {
  final String roomId;
  final String title;
  final Uri? avatarUrl;
  final String? directUserId;
  final String toneSeed;
  final String? lastEventId;
  final EventStatus? lastEventStatus;
  final MessageSummary? preview;
  final String? typingText;
  final String timeLabel;
  final int unread;
  final bool muted;
  final bool notEncrypted;
  final bool awaitingAcceptance;
  final String? pendingInviteSubtitle;
  final bool partnerLeft;
  final bool official;

  const ChatRowData({
    required this.roomId,
    required this.title,
    required this.avatarUrl,
    required this.directUserId,
    required this.toneSeed,
    required this.lastEventId,
    required this.lastEventStatus,
    required this.preview,
    required this.typingText,
    required this.timeLabel,
    required this.unread,
    required this.muted,
    required this.notEncrypted,
    required this.awaitingAcceptance,
    required this.pendingInviteSubtitle,
    required this.partnerLeft,
    required this.official,
  });

  static const prototype = ChatRowData(
    roomId: '',
    title: 'Name',
    avatarUrl: null,
    directUserId: null,
    toneSeed: '',
    lastEventId: null,
    lastEventStatus: null,
    preview: MessageSummary(kind: MessageKind.text, text: 'Preview'),
    typingText: null,
    timeLabel: '00:00',
    unread: 1,
    muted: false,
    notEncrypted: false,
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
    directUserId,
    toneSeed,
    lastEventId,
    lastEventStatus,
    preview,
    typingText,
    timeLabel,
    unread,
    muted,
    notEncrypted,
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
  required DateLabels labels,
}) {
  final display = roomInviteDisplay(room, labels.l10n);
  final event = room.lastEvent;
  final summary = event != null && isPreviewableLastEvent(event)
      ? summarize(labels.l10n, event)
      : null;
  final typing = typingIndicatorText(
    labels.l10n,
    room.typingUsers.where((user) => user.id != room.client.userID).toList(),
  );

  return ChatRowData(
    roomId: room.id,
    title: display.title,
    avatarUrl: display.avatarUrl,
    directUserId: room.directChatMatrixID,
    toneSeed: roomToneSeed(room),
    lastEventId: event?.eventId,
    lastEventStatus: event?.status,
    preview: summary,
    typingText: typing,
    timeLabel: event == null || display.awaitingAcceptance
        ? ''
        : labels.chatList(event.originServerTs, now: now),
    unread: displayedUnreadCount(unreadCorrections, room),
    muted: isRoomMuted(room),
    notEncrypted: !sendsEncrypted(room),
    awaitingAcceptance: display.awaitingAcceptance,
    pendingInviteSubtitle: display.awaitingAcceptance
        ? pendingInviteSubtitle(room, labels.l10n)
        : null,
    partnerLeft: display.partnerLeft,
    official: isOfficialZunoRoom(room),
  );
}
