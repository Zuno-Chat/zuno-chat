import 'dart:async';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../calls/notifications/call_notification_service.dart';
import '../errors/best_effort.dart';
import '../matrix/join_requests.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/matrix_ids.dart';
import '../matrix/room_title.dart';
import 'message_notification_content.dart';
import 'message_notification_poster.dart';

const _nameLimit = 40;

String joinRequestThread(String roomId, String userId) =>
    'knock:$roomId:$userId';

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
    threadKey: joinRequestThread(room.id, userId),
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
  final _posting = <String, Future<bool>>{};

  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onTimelineEvent.stream.listen(
      (event) => _post(client, event),
    );
    final syncSub = client.onSync.stream.listen(
      (update) => _withdrawAnswered(client, update),
    );
    ref.onDispose(() {
      sub.cancel();
      syncSub.cancel();
    });
  }

  void _post(Client client, Event event) {
    final content = joinRequestNotificationFor(client, event);
    if (content == null) return;
    final thread = content.thread;
    final posting = _posting[thread] = runBestEffort(
      () => postMessageNotification(
        content,
        client: client,
        includeMessageActions: false,
      ),
      label: 'join request notification',
    );
    unawaited(
      posting.whenComplete(() {
        if (identical(_posting[thread], posting)) _posting.remove(thread);
      }),
    );
  }

  Future<void> _withdrawAnswered(Client client, SyncUpdate update) async {
    final joined = update.rooms?.join ?? const <String, JoinedRoomUpdate>{};
    final answered = <String>{};
    for (final MapEntry(key: roomId, value: room) in joined.entries) {
      final latest = <String, Object?>{
        for (final event in [...?room.state, ...?room.timeline?.events])
          if (event.type == EventTypes.RoomMember &&
              event.stateKey != null &&
              event.stateKey != client.userID)
            event.stateKey!: event.content['membership'],
      };
      for (final MapEntry(key: userId, value: membership) in latest.entries) {
        if (membership != Membership.knock.name) {
          answered.add(joinRequestThread(roomId, userId));
        }
      }
    }
    if (answered.isEmpty) return;
    await Future.wait([for (final thread in answered) ?_posting[thread]]);
    await CallNotificationService.instance.cancelMessageNotificationsIfShowing(
      answered,
    );
  }
}
