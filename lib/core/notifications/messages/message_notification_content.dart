import 'package:clock/clock.dart';

import 'notification_thread.dart';

class MessageNotificationContent {
  final String roomId;
  final String? threadKey;
  final String title;

  final String text;
  final NotificationLineKind kind;

  final String? eventId;

  final bool isDirectChat;

  final String? senderId;
  final String? senderName;
  final Uri? senderAvatarUrl;
  final DateTime? timestamp;
  final int? unreadCount;
  final bool isPhoto;
  final bool quiet;

  const MessageNotificationContent({
    required this.roomId,
    this.threadKey,
    required this.title,
    required this.text,
    this.kind = NotificationLineKind.message,
    this.eventId,
    this.isDirectChat = true,
    this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    this.timestamp,
    this.unreadCount,
    this.isPhoto = false,
    this.quiet = false,
  });

  @override
  bool operator ==(Object other) =>
      other is MessageNotificationContent &&
      other.roomId == roomId &&
      other.threadKey == threadKey &&
      other.title == title &&
      other.text == text &&
      other.kind == kind &&
      other.eventId == eventId &&
      other.isDirectChat == isDirectChat &&
      other.senderId == senderId &&
      other.senderName == senderName &&
      other.senderAvatarUrl == senderAvatarUrl &&
      other.timestamp == timestamp &&
      other.unreadCount == unreadCount &&
      other.isPhoto == isPhoto &&
      other.quiet == quiet;

  @override
  int get hashCode => Object.hash(
    roomId,
    threadKey,
    title,
    text,
    kind,
    eventId,
    isDirectChat,
    senderId,
    senderName,
    senderAvatarUrl,
    timestamp,
    unreadCount,
    isPhoto,
    quiet,
  );

  String get thread => threadKey ?? roomId;

  NotificationLine toLine({
    StoredNotificationLine? previous,
    bool placeholder = false,
    String? imageUri,
    String? imageMimeType,
  }) =>
      StoredNotificationLine(
        eventId: eventId,
        senderId: senderId ?? previous?.senderId ?? roomId,
        kind: kind,
        timestamp:
            (placeholder ? previous?.timestamp : null) ??
            timestamp ??
            clock.now(),
        placeholder: placeholder,
        imageUri: imageUri ?? previous?.imageUri,
        imageMimeType: imageMimeType ?? previous?.imageMimeType,
        quiet: quiet,
      ).rendered(
        senderName: senderName ?? title,
        senderAvatarUrl: senderAvatarUrl,
        text: text,
      );

  NotificationThread threadOf(List<NotificationLine> lines) =>
      NotificationThread(
        roomId: roomId,
        key: thread,
        title: title,
        isGroupChat: !isDirectChat,
        lines: lines,
      );
}
