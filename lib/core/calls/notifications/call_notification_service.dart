import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../matrix/matrix_client_provider.dart';
import '../../notifications/message_notification_action.dart';
import '../../notifications/message_notification_content.dart';
import '../../notifications/notification_avatar_cache.dart';
import '../../notifications/notification_ids.dart';
import '../../notifications/notification_sound_player.dart';
import '../../notifications/notification_sound_settings.dart';
import '../../notifications/notification_thread_store.dart';
import '../../notifications/notified_events_store.dart';
import '../../push/push_timing.dart';
import 'ringing_call_store.dart';

export '../../notifications/notification_ids.dart'
    show messageNotificationIdFor;

const _channel = MethodChannel('zuno/calls');
const _callStyleChannel = MethodChannel('zuno/call_style');
const _conversationsChannel = MethodChannel('zuno/conversations');

const _ringChannelId = 'calls_ringing';
const _groupRingChannelId = 'calls_ringing_group';
const _ringNotificationId = 4002;
const _callsGroupId = 'calls_group';

const _groupMessagesChannelId = 'group_messages';
const _chatsGroupId = 'chats_group';
const _securityChannelId = 'security';

@visibleForTesting
const messagesChannelId = 'direct_messages';

enum CallNotificationAction { accept, decline }

class CallNotificationResponse {
  final CallNotificationAction action;
  final RingingCallInfo call;

  const CallNotificationResponse({required this.action, required this.call});
}

typedef RingingCallInfo = ({
  String roomId,
  String callId,
  String callerId,
  bool isVideo,
});

RingingCallInfo? ringingCallFromPayload(String? payload) {
  if (payload == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final roomId = decoded['roomId'];
  final callId = decoded['callId'];
  if (roomId is! String || callId is! String) return null;
  final callerId = decoded['callerId'];
  return (
    roomId: roomId,
    callId: callId,
    callerId: callerId is String ? callerId : '',
    isVideo: decoded['isVideo'] == true,
  );
}

Map<String, Object?>? _decodePayload(String? payload) {
  if (payload == null) return null;
  try {
    return jsonDecode(payload) as Map<String, Object?>;
  } on FormatException {
    return null;
  }
}

CallNotificationResponse? callNotificationResponseFrom({
  required String? actionId,
  required String? payload,
}) {
  final action = switch (actionId) {
    'accept' => CallNotificationAction.accept,
    'decline' => CallNotificationAction.decline,
    _ => null,
  };
  if (action == null) return null;
  final call = ringingCallFromPayload(payload);
  if (call == null) return null;
  return CallNotificationResponse(action: action, call: call);
}

class HeadlessCallDecline {
  final String roomId;
  final String callId;
  const HeadlessCallDecline({required this.roomId, required this.callId});
}

const _declinePortName = 'zuno_call_decline_port';

@pragma('vm:entry-point')
void _handleBackgroundCallResponse(NotificationResponse response) {
  final messageAction = messageNotificationActionFrom(
    actionId: response.actionId,
    payload: response.payload,
    input: response.input,
  );
  if (messageAction != null) {
    unawaited(_handleBackgroundMessageAction(messageAction));
    return;
  }
  if (response.actionId != 'decline') return;
  final decoded = _decodePayload(response.payload);
  if (decoded == null) return;
  final roomId = decoded['roomId'];
  final callId = decoded['callId'];
  if (roomId is! String || callId is! String) return;
  IsolateNameServer.lookupPortByName(_declinePortName)
      ?.send({'roomId': roomId, 'callId': callId});
}

Future<void> _handleBackgroundMessageAction(MessageNotificationAction action) =>
    runHeadlessMessageAction(
      action,
      clientBuilder: () async =>
          (await createMatrixClient(backgroundSync: false)).client,
    );

class CallNotificationService {
  CallNotificationService._();
  static final instance = CallNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _actionController =
      StreamController<CallNotificationResponse>.broadcast();
  bool _initialized = false;

  final _messageTapController = StreamController<String>.broadcast();
  final _newDeviceTapController = StreamController<void>.broadcast();
  final _headlessDeclineController =
      StreamController<HeadlessCallDecline>.broadcast();
  final _hangUpController = StreamController<void>.broadcast();
  final inPictureInPicture = ValueNotifier<bool>(false);

  Stream<CallNotificationResponse> get onAction => _actionController.stream;
  Stream<String> get onMessageTap => _messageTapController.stream;
  Stream<void> get onNewDeviceTap => _newDeviceTapController.stream;
  Stream<HeadlessCallDecline> get onHeadlessDecline =>
      _headlessDeclineController.stream;
  Stream<void> get onHangUp => _hangUpController.stream;

  @visibleForTesting
  void onActionForTest(CallNotificationResponse response) =>
      _actionController.add(response);

  @visibleForTesting
  void onMessageTapForTest(String roomId) => _messageTapController.add(roomId);

  @visibleForTesting
  void onNewDeviceTapForTest() => _newDeviceTapController.add(null);

  @visibleForTesting
  void onHeadlessDeclineForTest(HeadlessCallDecline decline) =>
      _headlessDeclineController.add(decline);

  Future<void> initialize({bool claimDeclinePort = true}) async {
    if (_initialized) return;
    _initialized = true;

    if (claimDeclinePort) _claimDeclinePort();

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'hangUpCall':
          _hangUpController.add(null);
        case 'pictureInPictureChanged':
          inPictureInPicture.value = call.arguments == true;
      }
      return null;
    });

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_zuno_mark'),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: _handleBackgroundCallResponse,
    );

    final android = _android;
    await android?.createNotificationChannelGroup(
      const AndroidNotificationChannelGroup(_callsGroupId, 'Calls'),
    );
    await android?.createNotificationChannelGroup(
      const AndroidNotificationChannelGroup(_chatsGroupId, 'Chats'),
    );
    for (final channel in _channels) {
      await android?.createNotificationChannel(channel);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static const _channels = [
    AndroidNotificationChannel(
      _ringChannelId,
      'Incoming calls',
      description: 'Ringing for an incoming voice or video call',
      importance: Importance.max,
      groupId: _callsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      messagesChannelId,
      'Messages',
      description: 'New messages in chats',
      importance: Importance.high,
      groupId: _chatsGroupId,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('message_tone'),
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      _groupRingChannelId,
      'Incoming room calls',
      description: 'Ringing for an incoming call in a room',
      importance: Importance.max,
      groupId: _callsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      _groupMessagesChannelId,
      'Room messages',
      description: 'New messages in rooms',
      importance: Importance.high,
      groupId: _chatsGroupId,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('message_tone'),
      enableVibration: false,
    ),
  ];

  ReceivePort? _declinePort;

  void _claimDeclinePort() {
    final receivePort = ReceivePort();
    _declinePort = receivePort;
    IsolateNameServer.removePortNameMapping(_declinePortName);
    IsolateNameServer.registerPortWithName(
      receivePort.sendPort,
      _declinePortName,
    );
    receivePort.listen((message) {
      if (message is! Map) return;
      final roomId = message['roomId'];
      final callId = message['callId'];
      if (roomId is String && callId is String) {
        _headlessDeclineController.add(
          HeadlessCallDecline(roomId: roomId, callId: callId),
        );
      }
    });
  }

  bool claimDeclinePortIfUnclaimed() {
    if (IsolateNameServer.lookupPortByName(_declinePortName) != null) {
      return false;
    }
    _claimDeclinePort();
    return true;
  }

  bool stillHoldsDeclinePort() {
    final held = _declinePort;
    if (held == null) return false;
    return IsolateNameServer.lookupPortByName(_declinePortName) ==
        held.sendPort;
  }

  void releaseDeclinePort() {
    IsolateNameServer.removePortNameMapping(_declinePortName);
    _declinePort?.close();
    _declinePort = null;
  }

  void _handleResponse(NotificationResponse response) {
    final call = callNotificationResponseFrom(
      actionId: response.actionId,
      payload: response.payload,
    );
    if (call != null) {
      _actionController.add(call);
      return;
    }
    final decoded = _decodePayload(response.payload);
    if (decoded == null) return;
    if (decoded['type'] == 'newDevice') {
      _newDeviceTapController.add(null);
      return;
    }
    if (decoded['type'] != 'message') return;
    final roomId = decoded['roomId'];
    if (roomId is String) _messageTapController.add(roomId);
  }

  Future<void> showIncomingCall({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
  }) async {
    await initialize();
    debugPrint(
      'zuno/push: posting ring for $callId '
      '(fullScreenIntentAllowed=${await fullScreenIntentAllowedOrNull()})',
    );
    try {
      await saveRingingCall(await SharedPreferences.getInstance(), (
        roomId: roomId,
        callId: callId,
        callerId: callerId,
        isVideo: isVideo,
      ));
    } catch (_) {}
    unawaited(NotificationSoundPlayer.instance.startIncomingRing());
    await _invoke('showIncomingCallStyle', {
      'channelId': isGroupCall ? _groupRingChannelId : _ringChannelId,
      'title': isVideo ? 'Incoming video call' : 'Incoming voice call',
      'callerName': callerName,
      'callerId': callerId,
      'isVideo': isVideo,
      'roomId': roomId,
      'callId': callId,
      'avatarBytes': avatarBytes,
    }, _callStyleChannel);
  }

  Future<void> cancelIncomingCall() async {
    await NotificationSoundPlayer.instance.stopIncomingRing();
    try {
      await clearRingingCall(await SharedPreferences.getInstance());
    } catch (_) {}
    await _invoke('cancelIncomingCallStyle', null, _callStyleChannel);
  }

  Future<RingingCallInfo?> activeRingCall() async {
    await initialize();
    try {
      final active = await _android?.getActiveNotifications();
      final showing = active?.any((n) => n.id == _ringNotificationId) ?? false;
      if (!showing) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return readRingingCall(prefs);
    } catch (_) {
      return null;
    }
  }

  Future<void> showMessage(
    MessageNotificationContent content, {
    bool includeMessageActions = false,
    Uint8List? senderAvatar,
    bool placeholder = false,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
    PushTiming? timing,
  }) async {
    await initialize();
    timing?.mark('init');
    final roomId = content.roomId;
    final title = content.title;
    final eventId = content.eventId;
    final senderAvatarUrl = content.senderAvatarUrl;
    final prefs = await _reloadedPrefs();
    if (eventId != null &&
        !refine &&
        prefs != null &&
        wasEventNotified(prefs, eventId)) {
      debugPrint('zuno/notifications: $eventId already shown, skipping');
      await retractPushNotice(roomId, eventId);
      return;
    }
    final noticed =
        !refine && eventId != null && await takePushNotice(roomId, eventId);
    if (noticed && prefs != null) await clearNotificationThread(prefs, roomId);
    timing?.mark('prefs');
    final notificationId = messageNotificationIdFor(roomId);
    final showing = (await _activeNotifications()).any(
      (n) => n.id == notificationId,
    );
    final lines = [
      ...?(await _showingThread(prefs, roomId, showing: showing))?.lines,
    ];
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
    );
    if (!replacing &&
        !refine &&
        eventId != null &&
        prefs != null &&
        wasPlaceholderShown(prefs, eventId)) {
      debugPrint('zuno/notifications: $eventId placeholder was dealt with');
      return;
    }
    if (!replacing) {
      lines.add(line);
    } else if (!placeholder) {
      lines[index] = line;
    }
    if (senderAvatar != null && senderAvatarUrl != null) {
      await NotificationAvatarCache.instance.write(
        senderAvatarUrl,
        senderAvatar,
      );
    }
    final plan = replacing || (noticed && showing)
        ? (alert: MessageAlert.silentUpdate, vibrate: false)
        : await NotificationSoundPlayer.instance.prepareMessageNotification(
            roomId: roomId,
          );
    timing?.mark('sound');
    final thread = NotificationThread(
      roomId: roomId,
      title: title,
      isGroupChat: !content.isDirectChat,
      lines: lines,
    );
    await _postThread(
      thread,
      alert: plan.alert,
      body: content.body,
      eventId: eventId,
      includeMessageActions: includeMessageActions,
      unreadCount: content.unreadCount,
      latestAvatar: senderAvatar,
      timing: timing,
    );
    if (prefs != null) await writeNotificationThread(prefs, thread);
    timing?.mark('store');
    if (plan.vibrate) {
      await NotificationSoundPlayer.instance.vibrateForMessage();
    }
    if (eventId == null) return;
    if (placeholder) {
      await _rememberPlaceholder(eventId);
    } else {
      await _rememberNotified(eventId);
    }
  }

  Future<void> _rememberPlaceholder(String eventId) async {
    try {
      await markPlaceholderShownOnDisk(
        await SharedPreferences.getInstance(),
        eventId,
      );
    } catch (_) {}
  }

  Future<void> retractPlaceholder(String roomId, String eventId) async {
    final prefs = await _reloadedPrefs();
    if (prefs == null) return;
    final thread = readNotificationThread(prefs, roomId);
    if (thread == null) return;
    final kept = thread.lines
        .where((l) => !(l.placeholder && l.eventId == eventId))
        .toList();
    if (kept.length == thread.lines.length) return;
    if (kept.isEmpty) {
      await cancelMessageNotification(roomId);
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
      alert: MessageAlert.silentUpdate,
      body: thread.isGroupChat ? '${last.senderName}: ${last.text}' : last.text,
      eventId: last.eventId,
      includeMessageActions: true,
      unreadCount: null,
      latestAvatar: null,
      timing: null,
    );
    await writeNotificationThread(prefs, remaining);
  }

  Future<SharedPreferences?> _reloadedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs;
    } catch (_) {
      return null;
    }
  }

  Future<NotificationThread?> _showingThread(
    SharedPreferences? prefs,
    String roomId, {
    required bool showing,
  }) async {
    if (prefs == null) return null;
    if (showing) return readNotificationThread(prefs, roomId);
    await clearNotificationThread(prefs, roomId);
    return null;
  }

  Future<List<ActiveNotification>> _activeNotifications() async {
    try {
      return await _android?.getActiveNotifications() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _postThread(
    NotificationThread thread, {
    required MessageAlert alert,
    required String body,
    required String? eventId,
    required bool includeMessageActions,
    required int? unreadCount,
    required Uint8List? latestAvatar,
    required PushTiming? timing,
  }) async {
    final roomId = thread.roomId;
    final (channelId, channelName) = thread.isGroupChat
        ? (_groupMessagesChannelId, 'Room messages')
        : (messagesChannelId, 'Messages');
    final avatars = await _avatarsFor(thread, latest: latestAvatar);
    timing?.mark('avatars');
    final latestLine = thread.lines.isEmpty ? null : thread.lines.last;
    final largeIcon = thread.isGroupChat || latestLine == null
        ? null
        : avatars[latestLine.senderId];
    await _pushConversationShortcut(thread, avatar: largeIcon);
    timing?.mark('shortcut');
    final actions = <AndroidNotificationAction>[
      if (includeMessageActions && eventId != null)
        const AndroidNotificationAction(
          'mark_read',
          'Mark as read',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      if (includeMessageActions)
        const AndroidNotificationAction(
          'reply',
          'Reply',
          showsUserInterface: false,
          cancelNotification: true,
          inputs: [AndroidNotificationActionInput(label: 'Message')],
        ),
    ];
    final when = latestLine?.timestamp.millisecondsSinceEpoch;
    await _plugin.show(
      id: messageNotificationIdFor(roomId),
      title: thread.title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          category: AndroidNotificationCategory.message,
          importance: Importance.high,
          priority: Priority.high,
          onlyAlertOnce: alert == MessageAlert.silentUpdate,
          silent: alert == MessageAlert.silent,
          styleInformation: MessagingStyleInformation(
            const Person(name: 'You', key: 'me'),
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
                  dataMimeType: line.imageMimeType,
                  dataUri: line.imageUri,
                ),
            ],
          ),
          largeIcon: largeIcon == null
              ? null
              : ByteArrayAndroidBitmap(largeIcon),
          shortcutId: roomId,
          number: unreadCount,
          when: when,
          showWhen: when != null,
          actions: actions.isEmpty ? null : actions,
        ),
      ),
      payload: jsonEncode({
        'type': 'message',
        'roomId': roomId,
        'eventId': ?eventId,
      }),
    );
    timing?.mark('show');
  }

  Future<Map<String, Uint8List>> _avatarsFor(
    NotificationThread thread, {
    required Uint8List? latest,
  }) async {
    final avatars = <String, Uint8List>{};
    for (final line in thread.lines.reversed) {
      if (avatars.containsKey(line.senderId)) continue;
      final url = line.senderAvatarUrl;
      if (url == null) continue;
      final bytes = await NotificationAvatarCache.instance.read(url);
      if (bytes != null) avatars[line.senderId] = bytes;
    }
    final latestLine = thread.lines.isEmpty ? null : thread.lines.last;
    if (latest != null && latestLine != null) {
      avatars[latestLine.senderId] = latest;
    }
    return avatars;
  }

  Future<void> _pushConversationShortcut(
    NotificationThread thread, {
    required Uint8List? avatar,
  }) async {
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
    } catch (e) {
      debugPrint('zuno/notifications: conversation shortcut skipped ($e)');
    }
  }

  Future<void> _rememberNotified(String eventId) async {
    try {
      await markEventNotifiedOnDisk(
        await SharedPreferences.getInstance(),
        eventId,
      );
    } catch (_) {}
  }

  Future<void> showNewDevice({
    required String deviceId,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.show(
      id: _newDeviceNotificationId(deviceId),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _securityChannelId,
          'Security alerts',
          channelDescription: 'New sign-ins to your account',
          category: AndroidNotificationCategory.status,
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode({'type': 'newDevice', 'deviceId': deviceId}),
    );
  }

  int _newDeviceNotificationId(String deviceId) =>
      ('device:$deviceId').hashCode & 0x7fffffff;

  Future<void> cancelMessageNotification(String roomId) async {
    await _plugin.cancel(id: messageNotificationIdFor(roomId));
    final prefs = await _reloadedPrefs();
    if (prefs != null) await clearNotificationThread(prefs, roomId);
  }

  Future<bool> takePushNotice(String roomId, String eventId) async {
    try {
      final taken = await _conversationsChannel.invokeMethod<bool>(
        'takePushNotice',
        {'roomId': roomId, 'eventId': eventId},
      );
      return taken ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> retractPushNotice(String roomId, String eventId) async {
    if (!await takePushNotice(roomId, eventId)) return;
    debugPrint('zuno/notifications: cancelling the instant notice for $roomId');
    await cancelMessageNotification(roomId);
  }

  Future<void> cancelMessageNotificationsIfShowing(
    Iterable<String> roomIds,
  ) async {
    final showing = (await _activeNotifications()).map((n) => n.id).toSet();
    for (final roomId in roomIds) {
      if (!showing.contains(messageNotificationIdFor(roomId))) continue;
      await cancelMessageNotification(roomId);
    }
  }

  static const _messageChannelIds = {
    messagesChannelId,
    _groupMessagesChannelId,
  };

  Future<void> cancelAllMessageNotifications() async {
    await initialize();
    for (final notification in await _activeNotifications()) {
      final id = notification.id;
      if (id == null) continue;
      if (!_messageChannelIds.contains(notification.channelId)) continue;
      await _plugin.cancel(id: id);
    }
    final prefs = await _reloadedPrefs();
    if (prefs != null) await clearAllNotificationThreads(prefs);
  }

  Future<String?> takeLaunchRoomIdFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final decoded = _decodePayload(details?.notificationResponse?.payload);
    if (decoded == null) return null;
    if (decoded['type'] != 'message') return null;
    final roomId = decoded['roomId'];
    return roomId is String ? roomId : null;
  }

  Future<CallNotificationResponse?>
  takeLaunchCallActionFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details?.notificationResponse;
    return callNotificationResponseFrom(
      actionId: response?.actionId,
      payload: response?.payload,
    );
  }

  Future<void> startOngoingCall({
    required String title,
    required bool withCamera,
  }) {
    return _invoke('startCallForegroundService', {
      'title': title,
      'text': 'Tap to return to the call',
      'withCamera': withCamera,
    });
  }

  Future<void> stopOngoingCall() => _invoke('stopCallForegroundService');

  Future<void> setShowOverLockscreen(bool show) =>
      _invoke('setShowOverLockscreen', {'show': show});

  Future<void> setProximityScreenOff(bool enabled) =>
      _invoke('setProximityScreenOff', {'enabled': enabled});

  Future<void> setPictureInPicture({
    required bool eligible,
    required int aspectWidth,
    required int aspectHeight,
  }) {
    return _invoke('setPictureInPicture', {
      'eligible': eligible,
      'aspectWidth': aspectWidth,
      'aspectHeight': aspectHeight,
    });
  }

  Future<bool> canUseFullScreenIntent() async =>
      await fullScreenIntentAllowedOrNull() ?? true;

  Future<bool?> fullScreenIntentAllowedOrNull() =>
      _invoke<bool>('canUseFullScreenIntent');

  Future<void> openFullScreenIntentSettings() =>
      _invoke('openFullScreenIntentSettings');

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
    MethodChannel channel = _channel,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}
