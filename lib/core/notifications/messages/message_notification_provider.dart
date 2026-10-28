import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../calls/matrixrtc/call_summary_message.dart';
import '../../calls/notifications/ring_over_lines.dart';
import '../../calls/platform/incoming_call_presenter.dart';
import '../../errors/caught_errors.dart';
import '../../l10n/l10n.dart';
import '../../matrix/currently_open_room_provider.dart';
import '../../matrix/event_display.dart';
import '../../matrix/late_decryptions.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../matrix/room_title.dart';
import '../../matrix/undecryptable_event.dart';
import '../../platform/platform_capabilities.dart';
import '../../push/nse/nse_app_channel.dart';
import '../../settings/app_preferences_provider.dart';
import '../settings/notification_preview.dart';
import '../settings/notify_me.dart';
import 'apns_alert_removal.dart';
import 'message_notification_content.dart';
import 'message_notification_image.dart';
import 'message_notification_poster.dart';
import 'message_notifications.dart';
import 'notification_room_cache.dart';

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

  final bool placeholder;

  const MessageNotificationDecision.notify(
    MessageNotificationContent this.content,
  ) : refusal = null,
      placeholder = false;

  const MessageNotificationDecision.floor(
    MessageNotificationContent this.content,
  ) : refusal = null,
      placeholder = true;

  const MessageNotificationDecision.refuse(
    MessageNotificationRefusal this.refusal,
  ) : content = null,
      placeholder = false;
}

MessageNotificationContent messageFloor(
  String roomId, {
  Room? room,
  String? eventId,
  String? senderId,
  String? roomName,
  String? senderName,
  bool quiet = false,
}) {
  final l10n = deviceLocalizations();
  final title = [roomName, if (room != null) roomTitle(room, l10n), senderName]
      .map((name) => name?.trim() ?? '')
      .firstWhere(
        (name) => name.isNotEmpty,
        orElse: () => l10n.notificationsNewMessage,
      );
  return MessageNotificationContent(
    roomId: roomId,
    title: title,
    body: l10n.notificationsTapToOpen,
    text: l10n.notificationsNewMessage,
    eventId: eventId,
    isDirectChat: room?.isDirectChat ?? true,
    senderId: senderId,
    senderName: title,
    quiet: quiet,
  );
}

MessageNotificationDecision messageNotificationFor(
  Client client,
  Event event, {
  required EvaluatedPushRuleAction pushRuleAction,
  required NotifyMe notifyMe,
  required String? currentlyOpenRoomId,
  NotificationPreview preview = NotificationPreview.full,
}) {
  if (event.senderId == client.userID) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.ownMessage,
    );
  }
  if (!isTimelineMessage(event)) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.notDisplayable,
    );
  }
  final locked = isUndecryptableEvent(event);
  if (event.type != EventTypes.Message && !locked) {
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

  final loud = notifyMe == NotifyMe.mentionsOnly
      ? pushRuleAction.highlight
      : pushRuleAction.notify;
  if (!loud && !pushRuleAction.notify) {
    return const MessageNotificationDecision.refuse(
      MessageNotificationRefusal.pushRule,
    );
  }

  final room = event.room;
  if (locked) {
    return MessageNotificationDecision.floor(
      messageFloor(
        room.id,
        room: room,
        eventId: event.eventId,
        senderId: event.senderId,
        quiet: !loud,
      ),
    );
  }
  final sender = room.unsafeGetUserFromMemoryOrFallback(event.senderId);
  final senderName = sender.calcDisplayname();
  final l10n = deviceLocalizations();
  final summary = summarize(l10n, event);
  final text =
      preview == NotificationPreview.nameOnly &&
          summary.kind != MessageKind.callSummary
      ? l10n.notificationsNewMessage
      : summary.text;
  final title = roomTitle(room, l10n);
  final body = room.isDirectChat
      ? text
      : l10n.notificationsSenderText(senderName, text);

  return MessageNotificationDecision.notify(
    MessageNotificationContent(
      roomId: room.id,
      title: title,
      body: body,
      text: text,
      eventId: event.eventId,
      isDirectChat: room.isDirectChat,
      senderId: event.senderId,
      senderName: senderName,
      senderAvatarUrl: sender.avatarUrl,
      timestamp: event.originServerTs,
      unreadCount: room.notificationCount,
      isPhoto: summary.kind == MessageKind.photo,
      quiet: !loud,
    ),
  );
}

final messageNotificationProvider =
    NotifierProvider<MessageNotificationNotifier, void>(
      MessageNotificationNotifier.new,
    );

typedef _AwaitedKey = ({String roomId, bool floorPosted});

class MessageNotificationNotifier extends Notifier<void> {
  final _roomCache = NotificationRoomCacheWriter();
  final _posting = <String, Set<Future<void>>>{};
  final _awaitingKeys = <String, _AwaitedKey>{};

  @override
  void build() {
    final client = ref.watch(matrixClientProvider);
    final sub = client.onTimelineEvent.stream.listen(
      (event) => _handleEvent(client, event),
    );
    final lateSub = LateDecryptions.of(client).decrypted
        .listen((event) => _handleLateKey(client, event));
    final syncSub = client.onSync.stream.listen(
      (update) => _handleSync(client, update),
    );
    ref.onDispose(() {
      sub.cancel();
      lateSub.cancel();
      syncSub.cancel();
      _awaitingKeys.clear();
    });
  }

  Future<void> _handleSync(Client client, SyncUpdate update) async {
    if (!_roomCache.hasWritten || notificationRoomCacheDirty(update)) {
      await _writeRoomCache(client);
    }
    final joined = update.rooms?.join ?? const <String, JoinedRoomUpdate>{};
    final readRooms = [
      for (final MapEntry(key: roomId, value: room) in joined.entries)
        if (room.unreadNotifications?.notificationCount == 0) roomId,
    ];
    final late = LateDecryptions.of(client);
    _awaitingKeys.removeWhere(
      (eventId, awaited) =>
          readRooms.contains(awaited.roomId) ||
          (!late.watches(eventId) && !_posting.containsKey(awaited.roomId)),
    );
    if (readRooms.isEmpty) return;
    if (ambientCapabilities.apnsRegistration) {
      await apnsAlertRemoval.removeForReadRooms(readRooms);
    }
    await Future.wait([for (final roomId in readRooms) ...?_posting[roomId]]);
    await MessageNotifications.instance.cancelMessageNotificationsIfShowing(
      readRooms,
    );
  }

  Future<void> _writeRoomCache(Client client) async {
    try {
      await _roomCache.write(
        await SharedPreferences.getInstance(),
        await notificationRoomEntriesOf(client),
      );
    } catch (error, stack) {
      reportCaught('notification room cache write', error, stack);
    }
  }

  Future<void> _handleLateKey(Client client, Event decrypted) async {
    var awaited = _awaitingKeys.remove(decrypted.eventId);
    await Future.wait([...?_posting[decrypted.room.id]]);
    awaited ??= _awaitingKeys.remove(decrypted.eventId);
    if (awaited == null) return;
    if (await _handleEvent(
      client,
      decrypted,
      refinesFloor: awaited.floorPosted,
    )) {
      return;
    }
    await MessageNotifications.instance.retractPlaceholder(
      decrypted.room.id,
      decrypted.eventId,
      preview: ref.read(notificationPreviewProvider),
    );
  }

  Future<bool> _handleEvent(
    Client client,
    Event event, {
    bool refinesFloor = false,
  }) async {
    if (client.prevBatch == null) return false;
    final roomId = event.room.id;
    final posted = Completer<void>();
    final inRoom = _posting.putIfAbsent(roomId, () => {})..add(posted.future);
    void settle() {
      if (!posted.isCompleted) posted.complete();
      inRoom.remove(posted.future);
      if (inRoom.isEmpty && identical(_posting[roomId], inRoom)) {
        _posting.remove(roomId);
      }
    }

    try {
      await loadRoomNameMembers(event.room);
      final presentsInFrontOnly = ref
          .read(platformCapabilitiesProvider)
          .nseNotifications;
      final preview = ref.read(notificationPreviewProvider);
      final pushRuleAction = client.pushruleEvaluator.match(event);
      final decision = messageNotificationFor(
        client,
        event,
        pushRuleAction: pushRuleAction,
        notifyMe: ref.read(notifyMeProvider),
        currentlyOpenRoomId: ref.read(currentlyOpenRoomIdProvider),
        preview: preview,
      );
      final content = decision.content;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final inFront =
          lifecycle == AppLifecycleState.resumed ||
          (presentsInFrontOnly && lifecycle == AppLifecycleState.inactive);
      void markShown() {
        if (presentsInFrontOnly) {
          unawaited(
            ref.read(nseAppChannelProvider).writeShown([event.eventId]),
          );
        }
      }

      if (content == null && pushRuleAction.notify) {
        await MessageNotifications.instance.retractPushNotice(
          roomId,
          event.eventId,
        );
      }
      if (decision.refusal == MessageNotificationRefusal.roomOpen) {
        markShown();
        return false;
      }
      if (content == null) return false;
      final ring = ref.read(incomingCallPresenterProvider);
      Future<bool> underRing() async =>
          decision.placeholder && await ringStandsInFor(event, ring);
      final quietInFront = content.quiet && inFront;
      final posts =
          !quietInFront &&
          (inFront || !presentsInFrontOnly || refinesFloor) &&
          !await underRing();
      if (decision.placeholder) {
        _awaitingKeys.putIfAbsent(
          event.eventId,
          () => (roomId: event.room.id, floorPosted: posts),
        );
      }
      if (quietInFront) markShown();
      if (!posts) return false;
      await postMessageNotification(
        content,
        client: client,
        preview: preview,
        placeholder: decision.placeholder,
        fetchImage: () => fetchMessageNotificationImage(event),
        onPosted: settle,
      );
      if (await underRing()) {
        await MessageNotifications.instance.retractPlaceholder(
          roomId,
          event.eventId,
          preview: preview,
        );
        return false;
      }
      markShown();
      return true;
    } finally {
      settle();
    }
  }
}
