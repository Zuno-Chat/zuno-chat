import 'package:matrix/matrix.dart';

import 'message_notification_content.dart';

MessageNotificationContent? verificationRequestNotificationFor(
  Client client,
  Event event,
) {
  if (event.type != EventTypes.Message) return null;
  if (event.messageType != EventTypes.KeyVerificationRequest) return null;
  if (event.senderId == client.userID) return null;
  if (event.content['to'] != client.userID) return null;

  final room = event.room;
  final sender = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
  final name = sender.calcDisplayname();
  const body = 'Wants to verify you';
  return MessageNotificationContent(
    roomId: room.id,
    title: name,
    body: body,
    text: body,
    eventId: event.eventId,
    isDirectChat: room.isDirectChat,
    senderId: event.senderId,
    senderName: name,
    senderAvatarUrl: sender.avatarUrl,
    timestamp: event.originServerTs,
  );
}
