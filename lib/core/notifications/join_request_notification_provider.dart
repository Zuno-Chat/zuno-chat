import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/join_requests.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/matrix_ids.dart';
import '../matrix/room_title.dart';
import 'message_notification_content.dart';
import 'message_notification_poster.dart';

const _nameLimit = 40;

String _requesterName(String userId, String? shown) {
  if (shown == null || shown.isEmpty) return withoutServer(userId);
  if (shown.characters.length <= _nameLimit) return shown;
  return '${shown.characters.take(_nameLimit)}…';
}

MessageNotificationContent? joinRequestNotificationFor(
  Client client,
  Event event,
) {
  if (event.type != EventTypes.RoomMember) return null;
  if (event.content['membership'] != Membership.knock.name) return null;
  final userId = event.stateKey;
  if (userId == null || userId == client.userID) return null;
  final room = event.room;
  if (room.isSpace || !canAnswerJoinRequests(room)) return null;
  final current = room.getState(EventTypes.RoomMember, userId);
  if (current != null &&
      current.content['membership'] != Membership.knock.name) {
    return null;
  }

  final name = _requesterName(
    userId,
    event.content.tryGet<String>('displayname')?.trim(),
  );
  final avatar = event.content.tryGet<String>('avatar_url');
  final body = '$name asks to join';
  return MessageNotificationContent(
    roomId: room.id,
    title: roomTitle(room),
    body: body,
    text: body,
    eventId: event.eventId,
    isDirectChat: false,
    senderId: userId,
    senderName: name,
    senderAvatarUrl: avatar == null ? null : Uri.tryParse(avatar),
    timestamp: event.originServerTs,
  );
}

final joinRequestNotificationProvider =
    NotifierProvider<JoinRequestNotificationNotifier, void>(
      JoinRequestNotificationNotifier.new,
    );

class JoinRequestNotificationNotifier extends Notifier<void> {
  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onTimelineEvent.stream.listen((event) {
      final content = joinRequestNotificationFor(client, event);
      if (content == null) return;
      postMessageNotification(
        content,
        client: client,
        includeMessageActions: false,
      );
    });
    ref.onDispose(sub.cancel);
  }
}
