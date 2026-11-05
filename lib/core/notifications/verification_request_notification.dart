import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import 'messages/message_notification_content.dart';
import 'messages/notification_thread_store.dart';

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
  return MessageNotificationContent(
    roomId: room.id,
    title: name,
    text: deviceLocalizations().notificationsWantsToVerify,
    kind: NotificationLineKind.notice,
    eventId: event.eventId,
    isDirectChat: room.isDirectChat,
    senderId: event.senderId,
    senderName: name,
    senderAvatarUrl: sender.avatarUrl,
    timestamp: event.originServerTs,
  );
}
