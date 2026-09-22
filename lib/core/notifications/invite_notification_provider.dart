import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../calls/notifications/call_notification_service.dart';
import '../matrix/matrix_client_provider.dart';
import 'message_notification_poster.dart';
import 'message_notification_provider.dart';

MessageNotificationContent? inviteNotificationFor(Client client, Event event) {
  if (event.type != EventTypes.RoomMember) return null;
  if (event.stateKey != client.userID) return null;
  if (event.content['membership'] != 'invite') return null;
  if (event.senderId == client.userID) return null;

  final room = event.room;
  final inviter = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
  final name = inviter.calcDisplayname();
  final body = room.name.isEmpty
      ? 'Invited you to chat'
      : 'Invited you to ${room.name}';
  return MessageNotificationContent(
    roomId: room.id,
    title: name,
    body: body,
    text: body,
    eventId: event.eventId,
    isDirectChat: room.isDirectChat,
    senderId: event.senderId,
    senderName: name,
    senderAvatarUrl: inviter.avatarUrl,
    timestamp: event.originServerTs,
  );
}

final roomInviteNotificationProvider =
    NotifierProvider<RoomInviteNotificationNotifier, void>(
      RoomInviteNotificationNotifier.new,
    );

class RoomInviteNotificationNotifier extends Notifier<void> {
  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onNotification.stream.listen(
      (event) => _handleEvent(client, event),
    );
    ref.onDispose(sub.cancel);
  }

  void _handleEvent(Client client, Event event) {
    final content = inviteNotificationFor(client, event);
    if (content == null) return;
    postMessageNotification(
      content,
      client: client,
      includeMessageActions: false,
    );
  }
}

Future<void> cancelInviteNotification(Room room) =>
    CallNotificationService.instance.cancelMessageNotification(room.id);
