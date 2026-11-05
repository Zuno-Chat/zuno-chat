import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../async/serial_lock.dart';
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
    required NotificationRenderer render,
    bool isMessage = false,
    Uint8List? senderAvatar,
    bool placeholder = false,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
    PushTiming? timing,
  }) => _rooms.run(
    content.thread,
    () => _showMessageInRoom(
      content,
      preview: preview,
      render: render,
      isMessage: isMessage,
      senderAvatar: senderAvatar,
      placeholder: placeholder,
      refine: refine,
      imageUri: imageUri,
      imageMimeType: imageMimeType,
      timing: timing,
    ),
  );

  Future<void> _showMessageInRoom(
    MessageNotificationContent content, {
    required NotificationPreview preview,
    required NotificationRenderer render,
    required bool isMessage,
    required Uint8List? senderAvatar,
    required bool placeholder,
    required bool refine,
    required String? imageUri,
    required String? imageMimeType,
    required PushTiming? timing,
  }) async {
    await _notifications.initialize();
    timing?.mark('init');
    final roomId = content.roomId;
    final key = content.thread;
    final inRoomThread = key == roomId;
    final eventId = content.eventId;
    final marks = await _withStore(
      (prefs) => (
        alreadyShown: eventId != null && wasEventNotified(prefs, eventId),
        placeholderDealtWith:
            eventId != null && wasPlaceholderShown(prefs, eventId),
        sound: readNotificationSoundSettings(prefs),
      ),
    );
    if (eventId != null && !refine && (marks?.alreadyShown ?? false)) {
      debugPrint('zuno/notifications: $eventId already shown, skipping');
      if (inRoomThread) await _retractPushNoticeInRoom(roomId, eventId);
      return;
    }
    final kept = _threads.read(key);
    final noticed =
        !refine && inRoomThread && await _takeNoticeFor(roomId, eventId);
    timing?.mark('prefs');
    final stored = noticed ? null : await kept;
    final (showingIds, readBack) = await (
      _showingIds(),
      _readBack(key, stored, preview),
    ).wait;
    final showing =
        showingIds?.contains(messageNotificationIdFor(key)) ?? false;
    final earlier = [if (showing) ...?stored?.lines];
    final index = eventId == null
        ? -1
        : earlier.indexWhere((l) => l.eventId == eventId);
    final replacing = index >= 0;
    if (refine && !replacing) {
      debugPrint('zuno/notifications: $eventId no longer showing, not refined');
      return;
    }
    final previous = replacing ? earlier[index] : null;
    final line = content.toLine(
      previous: previous,
      placeholder: placeholder,
      imageUri: imageUri,
      imageMimeType: imageMimeType,
    );
    if (!replacing && !refine && (marks?.placeholderDealtWith ?? false)) {
      debugPrint('zuno/notifications: $eventId placeholder was dealt with');
      return;
    }
    final added = line.stored;
    final placed = switch ((replacing, placeholder)) {
      (false, _) => _inTimeOrder(earlier, added),
      (true, true) => [...earlier]..[index] = added,
      (true, false) => _inTimeOrder(earlier, added, replacing: index),
    };
    final lines = await _displayed(
      roomId,
      placed,
      preview: preview,
      render: render,
      title: content.title,
      readBack: readBack,
      fresh: line,
    );
    timing?.mark('thread');
    if (noticed && showing) {
      NotificationSoundPlayer.instance.recordNoticeAlert(roomId);
    }
    final upgradesQuietLine =
        previous != null && previous.quiet && !added.quiet;
    final MessageAlertPlan plan;
    if (added.quiet) {
      plan = (
        alert: showing ? MessageAlert.silentUpdate : MessageAlert.silent,
        vibrate: false,
      );
    } else if ((replacing && !upgradesQuietLine) || (noticed && showing)) {
      plan = (alert: MessageAlert.silentUpdate, vibrate: false);
    } else if (noticed) {
      plan = (alert: MessageAlert.silent, vibrate: false);
    } else {
      plan = await NotificationSoundPlayer.instance.prepareMessageNotification(
        roomId: roomId,
        settings: marks?.sound,
      );
    }
    timing?.mark('sound');
    final posted = await _postThread(
      content.threadOf(lines),
      preview: preview,
      alert: plan.alert,
      isMessage: isMessage,
      unreadCount: content.unreadCount,
      freshAvatar: senderAvatar == null
          ? null
          : (senderId: added.senderId, bytes: senderAvatar),
      shortcut: !placeholder && !refine,
      timing: timing,
    );
    await Future.wait<void>([
      if (eventId != null && !refine)
        _withStore(
          (prefs) => placeholder
              ? markPlaceholderShownOnDisk(prefs, eventId)
              : markEventNotifiedOnDisk(prefs, eventId),
        ),
      _threads.write(posted, showing: _showingIds),
    ]);
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

  List<StoredNotificationLine> _inTimeOrder(
    List<StoredNotificationLine> lines,
    StoredNotificationLine line, {
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

  Future<List<WaitingLine>> showingWaitingLines() async {
    final waiting = await _threads.waitingLines();
    if (waiting.isEmpty) return const [];
    final showing = await _showingIds() ?? const {};
    return [
      for (final MapEntry(key: thread, value: lines) in waiting.entries)
        if (showing.contains(messageNotificationIdFor(thread))) ...lines,
    ];
  }

  Future<void> retractPlaceholder(
    String roomId,
    String eventId, {
    required NotificationPreview preview,
    required NotificationRenderer render,
  }) => _retractPlaceholders(
    roomId,
    (line) => line.eventId == eventId,
    preview: preview,
    render: render,
  );

  Future<void> retractPlaceholdersFrom(
    String roomId,
    String senderId, {
    required NotificationPreview preview,
    required NotificationRenderer render,
  }) => _retractPlaceholders(
    roomId,
    (line) => line.senderId == senderId,
    preview: preview,
    render: render,
  );

  Future<void> _retractPlaceholders(
    String roomId,
    bool Function(StoredNotificationLine line) retracts, {
    required NotificationPreview preview,
    required NotificationRenderer render,
  }) => _rooms.run(roomId, () async {
    final thread = await _threads.read(roomId);
    if (thread == null) return;
    final kept = thread.lines
        .where((line) => !(line.placeholder && retracts(line)))
        .toList();
    if (kept.length == thread.lines.length) return;
    final (showingIds, readBack) = await (
      _showingIds(),
      _readBack(roomId, thread, preview),
    ).wait;
    if (!(showingIds?.contains(messageNotificationIdFor(roomId)) ?? false)) {
      return;
    }
    await _withStore((prefs) async {
      for (final line in thread.lines) {
        if (kept.contains(line)) continue;
        if (line.eventId case final eventId?) {
          await forgetPlaceholderShownOnDisk(prefs, eventId);
        }
      }
    });
    if (kept.isEmpty) {
      await _cancelThread(roomId);
      return;
    }
    final title = await render.title(roomId);
    final posted = await _postThread(
      NotificationThread(
        roomId: roomId,
        title: title,
        isGroupChat: thread.isGroupChat,
        lines: await _displayed(
          roomId,
          kept,
          preview: preview,
          render: render,
          title: title,
          readBack: readBack,
        ),
      ),
      preview: preview,
      alert: MessageAlert.silentUpdate,
      isMessage: true,
      unreadCount: null,
      freshAvatar: null,
      shortcut: false,
      timing: null,
    );
    await _threads.write(posted, showing: _showingIds);
  });

  Future<void> settled() => _rooms.idle();

  NotificationThreadStore get _threads => NotificationThreadStore.instance;

  bool _showsHistory(NotificationPreview preview) =>
      _capabilities.conversationNotifications && preview.showsSenders;

  Future<List<NotificationLine>> _displayed(
    String roomId,
    List<StoredNotificationLine> placed, {
    required NotificationPreview preview,
    required NotificationRenderer render,
    required String title,
    required List<Message> readBack,
    NotificationLine? fresh,
  }) {
    final l10n = deviceLocalizations();
    final history = _showsHistory(preview);
    Future<NotificationLine> lineFor(StoredNotificationLine stored) async {
      if (fresh != null && identical(stored, fresh.stored)) return fresh;
      final shown =
          preview.showsSenders && (history || identical(stored, placed.last));
      if (!shown) return stored.untold(title, l10n);
      if (_takeShown(readBack, stored) case final message?) {
        return stored.rendered(
          senderName: message.person?.name ?? title,
          senderAvatarUrl: render.avatarOf(roomId, stored.senderId),
          text: message.text,
        );
      }
      return render.line(roomId, stored);
    }

    return Future.wait([for (final stored in placed) lineFor(stored)]);
  }

  Future<List<Message>> _readBack(
    String key,
    StoredNotificationThread? stored,
    NotificationPreview preview,
  ) async {
    if (!_showsHistory(preview) ||
        stored == null ||
        stored.lines.isEmpty ||
        stored.preview != preview) {
      return [];
    }
    return _notifications.shownMessages(messageNotificationIdFor(key));
  }

  Message? _takeShown(List<Message> shown, StoredNotificationLine stored) {
    final at = shown.indexWhere(
      (message) =>
          message.person?.key == stored.senderId &&
          message.timestamp.millisecondsSinceEpoch ==
              stored.timestamp.millisecondsSinceEpoch,
    );
    return at < 0 ? null : shown.removeAt(at);
  }

  Future<T?> _withStore<T>(
    FutureOr<T> Function(SharedPreferences prefs) step,
  ) => _store.run(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return await step(prefs);
    } catch (e, s) {
      reportCaught('notification store step', e, s);
      return null;
    }
  });

  bool _isMessageNotification(ActiveNotification notification) =>
      messageChannelIds.contains(notification.channelId) ||
      decodeNotificationPayload(notification.payload)?['type'] ==
          messagePayloadType;

  Future<StoredNotificationThread> _postThread(
    NotificationThread thread, {
    required NotificationPreview preview,
    required MessageAlert alert,
    required bool isMessage,
    required int? unreadCount,
    required ({String senderId, Uint8List bytes})? freshAvatar,
    required bool shortcut,
    required PushTiming? timing,
  }) async {
    final l10n = deviceLocalizations();
    final shown = thread.shownAt(preview, l10n);
    final roomId = shown.roomId;
    final latest = shown.lines.last.stored;
    final eventId = latest.eventId;
    final quiet = shown.lines.every((l) => l.stored.quiet);
    final (channelId, channelName) = switch ((quiet, shown.isGroupChat)) {
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
    final hidden = !preview.showsSenders;
    final offersActions = isMessage && preview == NotificationPreview.full;
    final avatars = await _avatarsFor(shown, fresh: freshAvatar);
    timing?.mark('avatars');
    final largeIcon = shown.isGroupChat ? null : avatars[latest.senderId];
    if (shortcut && !hidden) {
      await _pushConversationShortcut(shown, avatar: largeIcon);
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
    final when = latest.timestamp.millisecondsSinceEpoch;
    final interrupts = !quiet && alert != MessageAlert.silentUpdate;
    final playsTone = interrupts && alert == MessageAlert.tone;
    final threadIdentifier = switch ((hidden, _capabilities.nseNotifications)) {
      (true, _) => previewThread,
      (false, true) => await _threadIds.tokenFor(roomId) ?? previewThread,
      (false, false) => roomId,
    };
    await _plugin.show(
      id: messageNotificationIdFor(shown.key),
      title: shown.title,
      body: thread.bodyAt(preview, l10n),
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
              : _messagingStyle(shown, avatars, l10n),
          largeIcon: largeIcon == null
              ? null
              : ByteArrayAndroidBitmap(largeIcon),
          shortcutId: hidden ? null : roomId,
          number: unreadCount,
          when: when,
          showWhen: true,
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
    return shown.storedAt(preview);
  }

  MessagingStyleInformation _messagingStyle(
    NotificationThread thread,
    Map<String, Uint8List> avatars,
    AppLocalizations l10n,
  ) => MessagingStyleInformation(
    Person(name: l10n.commonYou, key: 'me'),
    conversationTitle: thread.isGroupChat ? thread.title : null,
    groupConversation: thread.isGroupChat,
    messages: [
      for (final line in thread.lines)
        Message(
          line.text,
          line.stored.timestamp,
          Person(
            name: line.senderName,
            key: line.stored.senderId,
            icon: switch (avatars[line.stored.senderId]) {
              final bytes? => ByteArrayAndroidIcon(bytes),
              null => null,
            },
          ),
          dataMimeType: line.stored.imageMimeType,
          dataUri: line.stored.imageUri,
        ),
    ],
  );

  Future<Map<String, Uint8List>> _avatarsFor(
    NotificationThread thread, {
    required ({String senderId, Uint8List bytes})? fresh,
  }) async {
    final avatars = <String, Uint8List>{};
    for (final line in thread.lines.reversed) {
      final senderId = line.stored.senderId;
      if (avatars.containsKey(senderId)) continue;
      final url = line.senderAvatarUrl;
      if (url == null) continue;
      if (fresh != null && fresh.senderId == senderId) {
        await NotificationAvatarCache.instance.write(url, fresh.bytes);
        avatars[senderId] = fresh.bytes;
        continue;
      }
      final bytes = await NotificationAvatarCache.instance.read(url);
      if (bytes != null) avatars[senderId] = bytes;
    }
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

  Future<Set<int>?> _showingIds() async {
    final active = await _notifications.activeNotifications();
    return active == null ? null : {for (final n in active) ?n.id};
  }

  Future<void> _cancelThread(String thread) async {
    await _plugin.cancel(id: messageNotificationIdFor(thread));
    await _threads.clear(thread);
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
    final showing = await _showingIds() ?? const {};
    for (final thread in threads) {
      if (!showing.contains(messageNotificationIdFor(thread))) continue;
      await cancelMessageNotification(thread);
    }
  }

  Future<void> cancelAllMessageNotifications() async {
    await _notifications.initialize();
    for (final notification
        in await _notifications.activeNotifications() ?? const []) {
      final id = notification.id;
      if (id == null) continue;
      if (!_isMessageNotification(notification)) continue;
      await _plugin.cancel(id: id);
    }
    await _threads.clearAll();
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
