class MessageNotificationContent {
  final String roomId;
  final String title;
  final String body;

  final String? text;

  final String? eventId;

  final bool isDirectChat;

  final String? senderId;
  final String? senderName;
  final Uri? senderAvatarUrl;
  final DateTime? timestamp;
  final int? unreadCount;
  final bool isPhoto;

  const MessageNotificationContent({
    required this.roomId,
    required this.title,
    required this.body,
    this.text,
    this.eventId,
    this.isDirectChat = true,
    this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    this.timestamp,
    this.unreadCount,
    this.isPhoto = false,
  });

  @override
  bool operator ==(Object other) =>
      other is MessageNotificationContent &&
      other.roomId == roomId &&
      other.title == title &&
      other.body == body &&
      other.text == text &&
      other.eventId == eventId &&
      other.isDirectChat == isDirectChat &&
      other.senderId == senderId &&
      other.senderName == senderName &&
      other.senderAvatarUrl == senderAvatarUrl &&
      other.timestamp == timestamp &&
      other.unreadCount == unreadCount &&
      other.isPhoto == isPhoto;

  @override
  int get hashCode => Object.hash(
    roomId,
    title,
    body,
    text,
    eventId,
    isDirectChat,
    senderId,
    senderName,
    senderAvatarUrl,
    timestamp,
    unreadCount,
    isPhoto,
  );
}
