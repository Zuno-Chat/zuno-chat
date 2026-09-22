import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../calls/matrixrtc/call_summary_message.dart';
import '../calls/notifications/call_notification_service.dart';
import '../matrix/currently_open_room_provider.dart';
import '../matrix/event_display.dart';
import '../matrix/matrix_client_provider.dart';
import '../matrix/room_title.dart';
import '../settings/app_preferences_provider.dart';
import 'message_notification_content.dart';
import 'message_notification_image.dart';
import 'message_notification_poster.dart';
import 'notification_room_cache.dart';
import 'notify_me.dart';

export 'message_notification_content.dart';

enum MessageNotificationRefusal {
  ownMessage,
  notDisplayable,
  notAMessage,
  callSummaryNotMissed,
  roomOpen,
  pushRule;

  String get label => switch (this) {
    MessageNotificationRefusal.ownMessage => 'own-message',
    MessageNotificationRefusal.notDisplayable => 'not-displayable',
    MessageNotificationRefusal.notAMessage => 'not-a-message',
    MessageNotificationRefusal.callSummaryNotMissed =>
      'call-summary-not-missed',
    MessageNotificationRefusal.roomOpen => 'room-open',
    MessageNotificationRefusal.pushRule => 'push-rule',
  };
}

class MessageNotificationDecision {
  final MessageNotificationContent? content;

  final MessageNotificationRefusal? refusal;

  const MessageNotificationDecision.notify(
    MessageNotificationContent this.content,
  ) : refusal = null;

  const MessageNotificationDecision.refuse(
    MessageNotificationRefusal this.refusal,
  ) : content = null;
}

MessageNotificationDecision messageNotificationFor(
  Client client,
  Event event, {
  required EvaluatedPushRuleAction pushRuleAction,
  required NotifyMe notifyMe,
  required String? currentlyOpenRoomId,
}) {
  if (event.senderId == client.userID) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.ownMessage,
    );
  }
  if (!isDisplayableTimelineEvent(event, showHiddenMessages: false)) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.notDisplayable,
    );
  }
  if (event.type != EventTypes.Message) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.notAMessage,
    );
  }
  if (isCallSummaryMessage(event.messageType) && !isMissedCallSummary(event)) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.callSummaryNotMissed,
    );
  }
  if (event.room.id == currentlyOpenRoomId) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.roomOpen,
    );
  }

  final shouldNotify = notifyMe == NotifyMe.mentionsOnly
      ? pushRuleAction.highlight
      : pushRuleAction.notify;
  if (!shouldNotify) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.pushRule,
    );
  }

  final room = event.room;
  final sender = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
  final senderName = sender.calcDisplayname();
  final summary = summarize(event);
  final title = roomTitle(room);
  final body = room.isDirectChat
      ? summary.text
      : '$senderName: ${summary.text}';

  return MessageNotificationDecision.notify(
    MessageNotificationContent(
      roomId: room.id,
      title: title,
      body: body,
      text: summary.text,
      eventId: event.eventId,
      isDirectChat: room.isDirectChat,
      senderId: event.senderId,
      senderName: senderName,
      senderAvatarUrl: sender.avatarUrl,
      timestamp: event.originServerTs,
      unreadCount: room.notificationCount,
      isPhoto: summary.kind == MessageKind.photo,
    ),
  );
}

final messageNotificationProvider =
    NotifierProvider<MessageNotificationNotifier, void>(
      MessageNotificationNotifier.new,
    );

class MessageNotificationNotifier extends Notifier<void> {
  final _roomCache = NotificationRoomCacheWriter();

  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onTimelineEvent.stream.listen(
      (event) => _handleEvent(client, event),
    );
    final syncSub = client.onSync.stream.listen(
      (update) => _handleSync(client, update),
    );
    ref.onDispose(() {
      sub.cancel();
      syncSub.cancel();
    });
  }

  Future<void> _handleSync(Client client, SyncUpdate update) async {
    if (!_roomCache.hasWritten || notificationRoomCacheDirty(update)) {
      await _writeRoomCache(client);
    }
    final joined = update.rooms?.join;
    if (joined == null) return;
    final readRooms = [
      for (final MapEntry(key: roomId, value: room) in joined.entries)
        if (room.unreadNotifications?.notificationCount == 0) roomId,
    ];
    if (readRooms.isEmpty) return;
    await CallNotificationService.instance.cancelMessageNotificationsIfShowing(
      readRooms,
    );
  }

  Future<void> _writeRoomCache(Client client) async {
    try {
      await _roomCache.write(
        await SharedPreferences.getInstance(),
        notificationRoomEntriesOf(client),
      );
    } catch (error) {
      debugPrint('zuno/notifications: room cache not written: $error');
    }
  }

  Future<void> _handleEvent(Client client, Event event) async {
    if (client.prevBatch == null) return;
    final content = messageNotificationFor(
      client,
      event,
      pushRuleAction: client.pushruleEvaluator.match(event),
      notifyMe: ref.read(notifyMeProvider),
      currentlyOpenRoomId: ref.read(currentlyOpenRoomIdProvider),
    ).content;
    if (content == null) return;
    await postMessageNotification(
      content,
      client: client,
      fetchImage: () => fetchMessageNotificationImage(event),
    );
  }
}
