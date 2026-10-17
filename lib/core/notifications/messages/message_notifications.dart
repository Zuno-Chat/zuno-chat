import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../async/serial_lock.dart';
import '../../brand.dart';
import '../../errors/caught_errors.dart';
import '../../l10n/l10n.dart';
import '../../platform/platform_capabilities.dart';
import '../../push/handling/push_timing.dart';
import '../../push/nse/opaque_thread_ids.dart';
import '../local_notifications.dart';
import '../settings/notification_preview.dart';
import '../settings/notification_sound_settings.dart';
import 'message_notification_content.dart';
import 'notification_avatar_cache.dart';
import 'notification_ids.dart';
import 'notification_sound_player.dart';
import 'notification_thread_store.dart';
import 'notified_events_store.dart';

const _conversationsChannel = MethodChannel('zuno/conversations');

typedef SilencedChannel = ({String id, String name});

List<SilencedChannel> silencedMessageChannels(
  Iterable<AndroidNotificationChannel> channels,
) => [
  for (final channel in channels)
    if (alertingMessageChannelIds.contains(channel.id) &&
        channel.importance.value < Importance.defaultImportance.value)
      (id: channel.id, name: channel.name),
];

String? _tappedRoomId(NotificationResponse response) {
  final decoded = decodeNotificationPayload(response.payload);
  if (decoded?['type'] != messagePayloadType) return null;
  final roomId = decoded?['roomId'];
  return roomId is String ? roomId : null;
}

class MessageNotifications {
  @visibleForTesting
  MessageNotifications({
    PlatformCapabilities? capabilities,
    OpaqueThreadIds? threadIds,
    LocalNotifications? notifications,
  }) : _injectedCapabilities = capabilities,
       _injectedThreadIds = threadIds,
       _injectedNotifications = notifications;
  static final instance = MessageNotifications();

  final PlatformCapabilities? _injectedCapabilities;
  final OpaqueThreadIds? _injectedThreadIds;
  final LocalNotifications? _injectedNotifications;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  OpaqueThreadIds get _threadIds =>
      _injectedThreadIds ?? OpaqueThreadIds.instance;

  LocalNotifications get _notifications =>
      _injectedNotifications ?? LocalNotifications.instance;

  FlutterLocalNotificationsPlugin get _plugin => _notifications.plugin;

  Stream<String> get onMessageTap => _notifications.onResponse.expand(
    (response) => [?_tappedRoomId(response)],
  );

  Future<String?> takeLaunchRoomIdFromNotification() async {
    final response = await _notifications.launchResponse();
    return response == null ? null : _tappedRoomId(response);
  }

  final _rooms = KeyedSerialLock();
  final _store = SerialLock();
  final _expectedNotices = <String, Set<String>>{};

  void Function() expectPushNotice(String roomId, String eventId) {
    final expected = _expectedNotices.putIfAbsent(roomId, () => {})
      ..add(eventId);
    return () {
      expected.remove(eventId);
      if (expected.isEmpty && identical(_expectedNotices[roomId], expected)) {
        _expectedNotices.remove(roomId);
      }
    };
  }

  Future<void> showMessage(
    MessageNotificationContent content, {
    required NotificationPreview preview,
    bool isMessage = false,
    Uint8List? senderAvatar,
    bool placeholder = false,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
    PushTiming? timing,
  }) async {
    await _notifications.initialize();
    timing?.mark('init');
    await _rooms.run(
      content.thread,
      () => _showMessageInRoom(
        content,
        preview: preview,
        isMessage: isMessage,
        senderAvatar: senderAvatar,
        placeholder: placeholder,
        refine: refine,
        imageUri: imageUri,
        imageMimeType: imageMimeType,
        timing: timing,
      ),
    );
  }

  Future<void> _showMessageInRoom(
    MessageNotificationContent content, {
    required NotificationPreview preview,
    required bool isMessage,
    required Uint8List? senderAvatar,
    required bool placeholder,
    required bool refine,
    required String? imageUri,
    required String? imageMimeType,
    required PushTiming? timing,
  }) async {
    final roomId = content.roomId;
    final key = content.thread;
    final inRoomThread = key == roomId;
    final title = content.title;
    final eventId = content.eventId;
    final senderAvatarUrl = content.senderAvatarUrl;
    final stored = await _withStore(
      (prefs) => (
        alreadyShown: eventId != null && wasEventNotified(prefs, eventId),
        placeholderDealtWith:
            eventId != null && wasPlaceholderShown(prefs, eventId),
        lines: readNotificationThread(prefs, key)?.lines,
        sound: readNotificationSoundSettings(prefs),
      ),
    );
    if (eventId != null && !refine && (stored?.alreadyShown ?? false)) {
      debugPrint('zuno/notifications: $eventId already shown, skipping');
      if (inRoomThread) await _retractPushNoticeInRoom(roomId, eventId);
      return;
    }
    final noticed =
        !refine && inRoomThread && await _takeNoticeFor(roomId, eventId);
    timing?.mark('prefs');
    final active = {
      for (final notification in await _notifications.activeNotifications())
        ?notification.id,
    };
    final showing = active.contains(messageNotificationIdFor(key));
    final lines = [if (showing && !noticed) ...?stored?.lines];
    timing?.mark('thread');
    final index = eventId == null
        ? -1
        : lines.indexWhere((l) => l.eventId == eventId);
    final replacing = index >= 0;
    if (refine && !replacing) {
      debugPrint('zuno/notifications: $eventId no longer showing, not refined');
      return;
    }
    final previous = replacing ? lines[index] : null;
    final line = NotificationLine(
      eventId: eventId,
      senderId: content.senderId ?? roomId,
      senderName: content.senderName ?? title,
      senderAvatarUrl: senderAvatarUrl ?? previous?.senderAvatarUrl,
      text: content.text ?? content.body,
      timestamp: content.timestamp ?? DateTime.now(),
      placeholder: placeholder,
      imageUri: imageUri ?? previous?.imageUri,
      imageMimeType: imageMimeType ?? previous?.imageMimeType,
      quiet: content.quiet,
    );
    if (!replacing && !refine && (stored?.placeholderDealtWith ?? false)) {
      debugPrint('zuno/notifications: $eventId placeholder was dealt with');
      return;
    }
    final placed = switch ((replacing, placeholder)) {
      (false, _) => _inTimeOrder(lines, line),
      (true, true) => lines,
      (true, false) => _inTimeOrder(lines, line, replacing: index),
    };
    if (senderAvatar != null && senderAvatarUrl != null) {
      await NotificationAvatarCache.instance.write(
        senderAvatarUrl,
        senderAvatar,
      );
    }
    if (noticed && showing) {
      NotificationSoundPlayer.instance.recordNoticeAlert(roomId);
    }
    final upgradesQuietLine = previous != null && previous.quiet && !line.quiet;
    final MessageAlertPlan plan;
    if (line.quiet) {
      plan = (
        alert: showing ? MessageAlert.silentUpdate : MessageAlert.silent,
        vibrate: false,
      );
    } else if ((replacing && !upgradesQuietLine) || (noticed && showing)) {
      plan = (alert: MessageAlert.silentUpdate, vibrate: false);
    } else {
      plan = await NotificationSoundPlayer.instance.prepareMessageNotification(
        roomId: roomId,
        settings: stored?.sound,
      );
    }
    timing?.mark('sound');
    final thread = NotificationThread(
      roomId: roomId,
      key: key,
      title: title,
      isGroupChat: !content.isDirectChat,
      lines: placed,
    );
    final latest = placed.last;
    final newest = identical(latest, line);
    await _postThread(
      thread,
      preview: preview,
      alert: plan.alert,
      body: newest ? content.body : _summaryOf(thread, latest),
      eventId: newest ? eventId : latest.eventId,
      isMessage: isMessage,
      unreadCount: content.unreadCount,
      freshAvatar: senderAvatar == null
          ? null
          : (senderId: line.senderId, bytes: senderAvatar),
      shortcut: !placeholder && !refine,
      timing: timing,
    );
    await _withStore((prefs) async {
      await writeNotificationThread(prefs, thread, showing: active);
      if (eventId == null || refine) return;
      if (placeholder) {
        await markPlaceholderShownOnDisk(prefs, eventId);
      } else {
        await markEventNotifiedOnDisk(prefs, eventId);
      }
    });
    timing?.mark('store');
    if (plan.vibrate) {
      await NotificationSoundPlayer.instance.vibrateForMessage();
    }
  }

  Future<bool> _takeNoticeFor(String roomId, String? eventId) async {
    if (eventId != null && await takePushNotice(roomId, eventId)) return true;
    for (final expected in [...?_expectedNotices[roomId]]) {
      if (expected == eventId) continue;
      if (await takePushNotice(roomId, expected)) return true;
    }
    return false;
  }

  List<NotificationLine> _inTimeOrder(
    List<NotificationLine> lines,
    NotificationLine line, {
    int? replacing,
  }) {
    final ordered = [...lines];
    if (replacing != null) {
      if (ordered[replacing].timestamp.isAtSameMomentAs(line.timestamp)) {
        return ordered..[replacing] = line;
      }
      ordered.removeAt(replacing);
    }
    var at = ordered.length;
    while (at > 0 && ordered[at - 1].timestamp.isAfter(line.timestamp)) {
      at--;
    }
    return ordered..insert(at, line);
  }

  String _summaryOf(NotificationThread thread, NotificationLine line) =>
      thread.isGroupChat ? '${line.senderName}: ${line.text}' : line.text;

  Future<void> retractPlaceholder(
    String roomId,
    String eventId, {
    required NotificationPreview preview,
  }) => _rooms.run(roomId, () async {
    final thread = await _withStore(
      (prefs) => readNotificationThread(prefs, roomId),
    );
    if (thread == null) return;
    final kept = thread.lines
        .where((l) => !(l.placeholder && l.eventId == eventId))
        .toList();
    if (kept.length == thread.lines.length) return;
    if (kept.isEmpty) {
      await _cancelThread(roomId);
      return;
    }
    final remaining = NotificationThread(
      roomId: roomId,
      title: thread.title,
      isGroupChat: thread.isGroupChat,
      lines: kept,
    );
    final last = kept.last;
    await _postThread(
      remaining,
      preview: preview,
      alert: MessageAlert.silentUpdate,
      body: _summaryOf(remaining, last),
      eventId: last.eventId,
      isMessage: true,
      unreadCount: null,
      freshAvatar: null,
      shortcut: false,
      timing: null,
    );
    await _withStore((prefs) => writeNotificationThread(prefs, remaining));
  });

  Future<T?> _withStore<T>(
    FutureOr<T> Function(SharedPreferences prefs) step,
  ) => _store.run(() async {
    final prefs = await _reloadedPrefs();
    if (prefs == null) return null;
    try {
      return await step(prefs);
    } catch (e, s) {
      reportCaught('notification store step', e, s);
      return null;
    }
  });

  Future<SharedPreferences?> _reloadedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs;
    } catch (e, s) {
      reportCaught('reload the notification store', e, s);
      return null;
    }
  }

  bool _isMessageNotification(ActiveNotification notification) =>
      messageChannelIds.contains(notification.channelId) ||
      decodeNotificationPayload(notification.payload)?['type'] ==
          messagePayloadType;

  Future<void> _postThread(
    NotificationThread thread, {
    required NotificationPreview preview,
    required MessageAlert alert,
    required String body,
    required String? eventId,
    required bool isMessage,
    required int? unreadCount,
    required ({String senderId, Uint8List bytes})? freshAvatar,
    required bool shortcut,
    required PushTiming? timing,
  }) async {
    final roomId = thread.roomId;
    final quiet = thread.lines.isNotEmpty && thread.lines.every((l) => l.quiet);
    final l10n = deviceLocalizations();
    final (channelId, channelName) = switch ((quiet, thread.isGroupChat)) {
      (true, _) => (
        quietMessagesChannelId,
        l10n.notificationsChannelQuietMessages,
      ),
      (false, true) => (
        groupMessagesChannelId,
        l10n.notificationsChannelRoomMessages,
      ),
      (false, false) => (
        messagesChannelId,
        l10n.notificationsChannelChatMessages,
      ),
    };
    final hidden = preview == NotificationPreview.nothing;
    final fullPreview = preview == NotificationPreview.full;
    final offersActions = isMessage && fullPreview;
    final avatars = hidden
        ? const <String, Uint8List>{}
        : await _avatarsFor(thread, fresh: freshAvatar);
    timing?.mark('avatars');
    final latestLine = thread.lines.isEmpty ? null : thread.lines.last;
    final largeIcon = thread.isGroupChat || latestLine == null
        ? null
        : avatars[latestLine.senderId];
    if (shortcut && !hidden) {
      await _pushConversationShortcut(thread, avatar: largeIcon);
      timing?.mark('shortcut');
    }
    final actions = <AndroidNotificationAction>[
      if (offersActions && eventId != null)
        AndroidNotificationAction(
          'mark_read',
          l10n.commonMarkAsRead,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      if (offersActions)
        AndroidNotificationAction(
          'reply',
          l10n.commonReply,
          showsUserInterface: false,
          cancelNotification: true,
          allowGeneratedReplies: false,
          inputs: [
            AndroidNotificationActionInput(label: l10n.commonMessageHint),
          ],
        ),
    ];
    final when = latestLine?.timestamp.millisecondsSinceEpoch;
    final interrupts = !quiet && alert != MessageAlert.silentUpdate;
    final playsTone = interrupts && alert == MessageAlert.tone;
    final threadIdentifier = switch ((hidden, _capabilities.nseNotifications)) {
      (true, _) => previewThread,
      (false, true) => await _threadIds.tokenFor(roomId) ?? previewThread,
      (false, false) => roomId,
    };
    await _plugin.show(
      id: messageNotificationIdFor(thread.key),
      title: hidden ? zunoName : thread.title,
      body: hidden ? l10n.notificationsNewMessage : body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          category: AndroidNotificationCategory.message,
          importance: quiet ? Importance.low : Importance.high,
          priority: quiet ? Priority.low : Priority.high,
          onlyAlertOnce: alert == MessageAlert.silentUpdate,
          silent: alert == MessageAlert.silent,
          styleInformation: hidden
              ? null
              : _messagingStyle(
                  thread,
                  avatars,
                  withImages: fullPreview,
                  l10n: l10n,
                ),
          largeIcon: largeIcon == null
              ? null
              : ByteArrayAndroidBitmap(largeIcon),
          shortcutId: hidden ? null : roomId,
          number: unreadCount,
          when: when,
          showWhen: when != null,
          actions: actions.isEmpty ? null : actions,
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: threadIdentifier,
          categoryIdentifier: darwinMessageCategory(
            isMessage: isMessage,
            offersActions: offersActions,
            eventId: eventId,
          ),
          presentAlert: interrupts,
          presentBanner: interrupts,
          presentList: true,
          presentSound: playsTone,
          sound: playsTone ? darwinMessageToneSound : null,
          interruptionLevel: interrupts
              ? InterruptionLevel.active
              : InterruptionLevel.passive,
        ),
      ),
      payload: jsonEncode({
        'type': messagePayloadType,
        'roomId': roomId,
        'eventId': ?eventId,
      }),
    );
    timing?.mark('show');
  }

  MessagingStyleInformation _messagingStyle(
    NotificationThread thread,
    Map<String, Uint8List> avatars, {
    required bool withImages,
    required AppLocalizations l10n,
  }) => MessagingStyleInformation(
    Person(name: l10n.commonYou, key: 'me'),
    conversationTitle: thread.isGroupChat ? thread.title : null,
    groupConversation: thread.isGroupChat,
    messages: [
      for (final line in thread.lines)
        Message(
          line.text,
          line.timestamp,
          Person(
            name: line.senderName,
            key: line.senderId,
            icon: switch (avatars[line.senderId]) {
              final bytes? => ByteArrayAndroidIcon(bytes),
              null => null,
            },
          ),
          dataMimeType: withImages ? line.imageMimeType : null,
          dataUri: withImages ? line.imageUri : null,
        ),
    ],
  );

  Future<Map<String, Uint8List>> _avatarsFor(
    NotificationThread thread, {
    required ({String senderId, Uint8List bytes})? fresh,
  }) async {
    final avatars = <String, Uint8List>{};
    for (final line in thread.lines.reversed) {
      if (avatars.containsKey(line.senderId)) continue;
      final url = line.senderAvatarUrl;
      if (url == null) continue;
      final bytes = await NotificationAvatarCache.instance.read(url);
      if (bytes != null) avatars[line.senderId] = bytes;
    }
    if (fresh != null) avatars[fresh.senderId] = fresh.bytes;
    return avatars;
  }

  Future<void> _pushConversationShortcut(
    NotificationThread thread, {
    required Uint8List? avatar,
  }) async {
    if (!_capabilities.notificationAvatars) return;
    try {
      await _conversationsChannel.invokeMethod<void>(
        'pushConversationShortcut',
        {
          'roomId': thread.roomId,
          'label': thread.title,
          'isGroup': thread.isGroupChat,
          'avatarBytes': avatar,
        },
      );
    } catch (e, s) {
      reportCaught('push a conversation shortcut', e, s);
    }
  }

  Future<void> cancelMessageNotification(String thread) =>
      _rooms.run(thread, () => _cancelThread(thread));

  Future<void> _cancelThread(String thread) async {
    await _plugin.cancel(id: messageNotificationIdFor(thread));
    await _withStore((prefs) => clearNotificationThread(prefs, thread));
  }

  Future<bool> takePushNotice(String roomId, String eventId) async {
    if (!_capabilities.instantPushNotices) return false;
    try {
      final taken = await _conversationsChannel.invokeMethod<bool>(
        'takePushNotice',
        {'roomId': roomId, 'eventId': eventId},
      );
      return taken ?? false;
    } catch (e, s) {
      reportCaught('take a push notice', e, s);
      return false;
    }
  }

  Future<void> retractPushNotice(String roomId, String eventId) =>
      _rooms.run(roomId, () => _retractPushNoticeInRoom(roomId, eventId));

  Future<void> _retractPushNoticeInRoom(String roomId, String eventId) async {
    if (!await takePushNotice(roomId, eventId)) return;
    debugPrint('zuno/notifications: cancelling the instant notice for $roomId');
    await _cancelThread(roomId);
  }

  Future<void> cancelMessageNotificationsIfShowing(
    Iterable<String> threads,
  ) async {
    final showing = (await _notifications.activeNotifications())
        .map((n) => n.id)
        .toSet();
    for (final thread in threads) {
      if (!showing.contains(messageNotificationIdFor(thread))) continue;
      await cancelMessageNotification(thread);
    }
  }

  Future<void> cancelAllMessageNotifications() async {
    await _notifications.initialize();
    for (final notification in await _notifications.activeNotifications()) {
      final id = notification.id;
      if (id == null) continue;
      if (!_isMessageNotification(notification)) continue;
      await _plugin.cancel(id: id);
    }
    await _withStore(clearAllNotificationThreads);
  }

  Future<List<SilencedChannel>> silencedChannels() async {
    try {
      return silencedMessageChannels(
        await _notifications.android?.getNotificationChannels() ?? const [],
      );
    } catch (e, s) {
      reportCaught('read notification channels', e, s);
      return const [];
    }
  }
}
