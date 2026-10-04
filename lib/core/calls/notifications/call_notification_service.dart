import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:shared_preferences/shared_preferences.dart';

import '../../matrix/matrix_client_provider.dart';
import '../../network/user_agent.dart';
import '../../notifications/message_notification_action.dart';
import '../../notifications/message_notification_content.dart';
import '../../notifications/notification_avatar_cache.dart';
import '../../notifications/notification_ids.dart';
import '../../notifications/notification_preview.dart';
import '../../notifications/notification_sound_player.dart';
import '../../notifications/notification_sound_settings.dart';
import '../../notifications/notification_thread_store.dart';
import '../../notifications/notified_events_store.dart';
import '../../platform/platform_capabilities.dart';
import '../../push/push_timing.dart';
import '../../push/read_model/opaque_thread_ids.dart';
import '../platform/native_ring.dart';
import '../serial_lock.dart';
import 'call_decline_action.dart';
import 'live_isolate_route.dart';

export '../../notifications/notification_ids.dart'
    show messageNotificationIdFor;
export 'live_isolate_route.dart'
    show answersPing, handOffToLiveIsolate, liveRouteAcceptWithin;

const _channel = MethodChannel('zuno/calls');
const _conversationsChannel = MethodChannel('zuno/conversations');

const ringChannelId = 'calls_ringing';
const groupRingChannelId = 'calls_ringing_group';
const _callsGroupId = 'calls_group';

const _groupMessagesChannelId = 'group_messages';
const _quietMessagesChannelId = 'quiet_messages';
const _chatsGroupId = 'chats_group';
const _securityChannelId = 'security';
const _accountGroupId = 'account_group';

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

typedef SystemMute = ({String callId, bool muted});

RingingCallInfo? ringingCallFromPayload(String? payload) {
  if (payload == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  return _ringingCallFrom(decoded);
}

RingingCallInfo? _ringingCallFrom(Object? value) {
  if (value is! Map) return null;
  final roomId = value['roomId'];
  final callId = value['callId'];
  if (roomId is! String || callId is! String) return null;
  final callerId = value['callerId'];
  return (
    roomId: roomId,
    callId: callId,
    callerId: callerId is String ? callerId : '',
    isVideo: value['isVideo'] == true,
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

typedef SilencedChannel = ({String id, String name});

const alertingMessageChannelIds = {messagesChannelId, _groupMessagesChannelId};
const ringChannelIds = {ringChannelId, groupRingChannelId};

List<SilencedChannel> silencedMessageChannels(
  Iterable<AndroidNotificationChannel> channels,
) => [
  for (final channel in channels)
    if (alertingMessageChannelIds.contains(channel.id) &&
        channel.importance.value < Importance.defaultImportance.value)
      (id: channel.id, name: channel.name),
];

String? darwinMessageCategory({
  required bool includeMessageActions,
  required String? eventId,
}) => switch ((includeMessageActions, eventId)) {
  (false, _) => null,
  (true, null) => CallNotificationService._replyOnlyCategoryId,
  (true, _) => CallNotificationService._markReadCategoryId,
};

class HeadlessCallDecline {
  final String roomId;
  final String callId;
  final LiveRouteMessage? route;

  const HeadlessCallDecline({
    required this.roomId,
    required this.callId,
    this.route,
  });

  void finished() => route?.finish();
}

class HandedMessageAction {
  HandedMessageAction(this.action, {this.route, this.txid});

  final MessageNotificationAction action;
  final LiveRouteMessage? route;
  final String? txid;

  void finished() => route?.finish();
}

const declinePortName = 'zuno_call_decline_port';
const messageActionPortName = 'zuno_message_action_port';

@pragma('vm:entry-point')
void _handleBackgroundCallResponse(NotificationResponse response) {
  final messageAction = messageNotificationActionFrom(
    actionId: response.actionId,
    payload: response.payload,
    input: response.input,
  );
  if (messageAction != null) {
    unawaited(
      runHeadlessMessageAction(
        messageAction,
        handOff: (action, txid) => handOffToLiveIsolate(
          messageActionPortName,
          encodeMessageAction(action, txid: txid),
        ),
        clientBuilder: _oneShotClient,
      ),
    );
    return;
  }
  if (response.actionId != 'decline') return;
  final decoded = _decodePayload(response.payload);
  if (decoded == null) return;
  final roomId = decoded['roomId'];
  final callId = decoded['callId'];
  if (roomId is! String || callId is! String) return;
  unawaited(
    runHeadlessCallDecline(
      roomId: roomId,
      callId: callId,
      handOff: () => handOffToLiveIsolate(declinePortName, {
        'roomId': roomId,
        'callId': callId,
      }),
      clientBuilder: _oneShotClient,
    ),
  );
}

Future<Client> _oneShotClient() async {
  await installUserAgent();
  return (await createMatrixClient(backgroundSync: false)).client;
}

class CallNotificationService {
  @visibleForTesting
  CallNotificationService({
    PlatformCapabilities? capabilities,
    OpaqueThreadIds? threadIds,
  }) : _injectedCapabilities = capabilities,
       _injectedThreadIds = threadIds;
  static final instance = CallNotificationService();

  final PlatformCapabilities? _injectedCapabilities;
  final OpaqueThreadIds? _injectedThreadIds;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  OpaqueThreadIds get _threadIds =>
      _injectedThreadIds ?? OpaqueThreadIds.instance;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _actionController =
      StreamController<CallNotificationResponse>.broadcast();
  bool _initialized = false;

  final _messageTapController = StreamController<String>.broadcast();
  final _newDeviceTapController = StreamController<void>.broadcast();
  late final StreamController<HeadlessCallDecline> _headlessDeclineController =
      StreamController.broadcast(
        onListen: () => _releaseHeld(
          _heldDeclines,
          _headlessDeclineController,
          routeOf: (decline) => decline.route,
        ),
      );
  late final StreamController<HandedMessageAction> _messageActionController =
      StreamController.broadcast(
        onListen: () => _releaseHeld(
          _heldActions,
          _messageActionController,
          routeOf: (action) => action.route,
        ),
      );
  final _hangUpController = StreamController<String?>.broadcast();
  final _systemMuteController = StreamController<SystemMute>.broadcast();
  final _ringEndedController = StreamController<RingingCallInfo>.broadcast();
  final _systemCallFailedController = StreamController<String>.broadcast();
  final _systemRingingController =
      StreamController<RingingCallInfo>.broadcast();
  final _nativeRingController = StreamController<NativeRing>.broadcast();
  final _audioRouteController =
      StreamController<Map<Object?, Object?>>.broadcast();
  final inPictureInPicture = ValueNotifier<bool>(false);

  Stream<CallNotificationResponse> get onAction => _actionController.stream;
  Stream<String> get onMessageTap => _messageTapController.stream;
  Stream<void> get onNewDeviceTap => _newDeviceTapController.stream;
  Stream<HeadlessCallDecline> get onHeadlessDecline =>
      _headlessDeclineController.stream;
  Stream<HandedMessageAction> get onMessageAction =>
      _messageActionController.stream;
  Stream<String?> get onHangUp => _hangUpController.stream;
  Stream<SystemMute> get onSystemMute => _systemMuteController.stream;
  Stream<RingingCallInfo> get onRingEnded => _ringEndedController.stream;
  Stream<String> get onSystemCallFailed => _systemCallFailedController.stream;
  Stream<RingingCallInfo> get onSystemRinging =>
      _systemRingingController.stream;
  Stream<NativeRing> get onNativeRing => _nativeRingController.stream;
  Stream<Map<Object?, Object?>> get onAudioRouteChanged =>
      _audioRouteController.stream;

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

  @visibleForTesting
  void onMessageActionForTest(HandedMessageAction action) =>
      _messageActionController.add(action);

  Future<void> initialize({bool claimDeclinePort = true}) async {
    if (claimDeclinePort && !_ownsLiveRoutes) {
      _ownsLiveRoutes = true;
      reclaimLiveRoutes();
    }
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      _handleNativeCall(call.method, call.arguments);
      return null;
    });
    if (_capabilities.callKit) await _invoke<void>('resetSystemCalls');

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings(
          '@drawable/ic_stat_zuno_mark',
        ),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          notificationCategories: _capabilities.nativeNotificationActions
              ? const <DarwinNotificationCategory>[]
              : _messageCategories,
        ),
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
    await android?.createNotificationChannelGroup(
      const AndroidNotificationChannelGroup(_accountGroupId, 'Account'),
    );
    for (final channel in _channels) {
      await android?.createNotificationChannel(channel);
    }
    for (final channelId in _retiredChannelIds) {
      await android?.deleteNotificationChannel(channelId: channelId);
    }
  }

  static const _markReadCategoryId = 'message';
  static const _replyOnlyCategoryId = 'reply';

  static final _replyAction = DarwinNotificationAction.text(
    'reply',
    'Reply',
    buttonTitle: 'Send',
    placeholder: 'Message',
  );

  static final _messageCategories = [
    DarwinNotificationCategory(
      _markReadCategoryId,
      actions: [
        _replyAction,
        DarwinNotificationAction.plain('mark_read', 'Mark as read'),
      ],
    ),
    DarwinNotificationCategory(_replyOnlyCategoryId, actions: [_replyAction]),
  ];

  static const _retiredChannelIds = [
    'messages',
    'messages_group',
    'messages_sound_v1',
    'messages_group_sound_v1',
  ];

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static const _channels = [
    AndroidNotificationChannel(
      ringChannelId,
      'Incoming calls',
      description: 'Ringing for a call in a chat',
      importance: Importance.max,
      groupId: _callsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      messagesChannelId,
      'Chat messages',
      description: 'New messages in one-to-one chats',
      importance: Importance.high,
      groupId: _chatsGroupId,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('message_tone'),
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      groupRingChannelId,
      'Incoming room calls',
      description: 'Ringing for a call in a room',
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
    AndroidNotificationChannel(
      _quietMessagesChannelId,
      'Quiet messages',
      description:
          'Messages that do not mention you, while notifications are set to '
          'mentions only',
      importance: Importance.low,
      groupId: _chatsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      _securityChannelId,
      'New sign-ins',
      description: 'A new device signed in to your account',
      importance: Importance.max,
      groupId: _accountGroupId,
    ),
  ];

  bool _ownsLiveRoutes = false;
  ReceivePort? _declinePort;
  ReceivePort? _actionPort;
  final _heldDeclines = <HeadlessCallDecline>[];
  final _heldActions = <HandedMessageAction>[];

  void reclaimLiveRoutes() {
    if (!_ownsLiveRoutes) return;
    _declinePort = _route(declinePortName, _declinePort, _onDecline);
    _actionPort = _route(messageActionPortName, _actionPort, _onMessageAction);
  }

  ReceivePort _route(
    String name,
    ReceivePort? current,
    void Function(Object? message) onMessage,
  ) {
    final port = current ?? (ReceivePort()..listen(onMessage));
    if (IsolateNameServer.lookupPortByName(name) != port.sendPort) {
      IsolateNameServer.removePortNameMapping(name);
      IsolateNameServer.registerPortWithName(port.sendPort, name);
    }
    return port;
  }

  void _onDecline(Object? message) {
    if (answerPing(message)) return;
    final route = LiveRouteMessage.from(message);
    final roomId = route?.body['roomId'];
    final callId = route?.body['callId'];
    if (route == null ||
        roomId is! String ||
        callId is! String ||
        route.stale) {
      route?.refuse();
      return;
    }
    final decline = HeadlessCallDecline(
      roomId: roomId,
      callId: callId,
      route: route,
    );
    if (_headlessDeclineController.hasListener) {
      route.accept();
      _headlessDeclineController.add(decline);
    } else if (_ownsLiveRoutes) {
      route.accept();
      _heldDeclines.add(decline);
    } else {
      route.refuse();
    }
  }

  void _onMessageAction(Object? message) {
    if (answerPing(message)) return;
    final route = LiveRouteMessage.from(message);
    final action = decodeMessageAction(route?.body);
    if (route == null || action == null || route.stale) {
      route?.refuse();
      return;
    }
    route.accept();
    final handed = HandedMessageAction(
      action,
      route: route,
      txid: handedTxidOf(route.body),
    );
    if (_messageActionController.hasListener) {
      _messageActionController.add(handed);
    } else {
      _heldActions.add(handed);
    }
  }

  void _releaseHeld<T>(
    List<T> held,
    StreamController<T> controller, {
    required LiveRouteMessage? Function(T entry) routeOf,
  }) {
    final waiting = [...held];
    held.clear();
    for (final entry in waiting) {
      if (_senderGaveUp(routeOf(entry))) {
        debugPrint('zuno/calls: dropping held work its sender already did');
        continue;
      }
      controller.add(entry);
    }
  }

  bool _senderGaveUp(LiveRouteMessage? route) {
    final sentAt = route?.body['sentAt'];
    if (sentAt is! int) return false;
    final age = now().millisecondsSinceEpoch - sentAt;
    return age > liveRouteDoneWithin.inMilliseconds;
  }

  Future<bool> claimDeclinePortUnlessLive({
    Duration within = liveRouteProbeWithin,
  }) async {
    final mapped = IsolateNameServer.lookupPortByName(declinePortName);
    if (mapped != null) {
      if (mapped == _declinePort?.sendPort) return false;
      if (await answersPing(mapped, within: within)) return false;
      if (IsolateNameServer.lookupPortByName(declinePortName) != mapped) {
        return false;
      }
      debugPrint('zuno/calls: the decline route answered nothing, taking it');
    }
    _declinePort = _route(declinePortName, _declinePort, _onDecline);
    return true;
  }

  bool stillHoldsDeclinePort() {
    final held = _declinePort;
    if (held == null) return false;
    return IsolateNameServer.lookupPortByName(declinePortName) == held.sendPort;
  }

  void releaseDeclinePort() {
    final held = _declinePort;
    _declinePort = null;
    if (held == null) return;
    if (IsolateNameServer.lookupPortByName(declinePortName) == held.sendPort) {
      IsolateNameServer.removePortNameMapping(declinePortName);
    }
    held.close();
  }

  CallNotificationResponse? _pendingNativeCallAction;

  void _handleNativeCall(String method, Object? arguments) {
    switch (method) {
      case 'hangUpCall':
        _hangUpController.add(_callIdFrom(arguments));
      case 'pictureInPictureChanged':
        inPictureInPicture.value = arguments == true;
      case 'answerCall':
        _deliverNativeCallAction(CallNotificationAction.accept, arguments);
      case 'declineCall':
        _deliverNativeCallAction(CallNotificationAction.decline, arguments);
      case 'setMuted':
        final callId = _callIdFrom(arguments);
        final muted = arguments is Map ? arguments['muted'] : null;
        if (callId != null && muted is bool) {
          _systemMuteController.add((callId: callId, muted: muted));
        }
      case 'ringEnded':
        final call = _ringingCallFrom(arguments);
        if (call != null) _ringEndedController.add(call);
      case 'callFailed':
        final callId = _callIdFrom(arguments);
        if (callId != null) _systemCallFailedController.add(callId);
      case 'ringing':
        final call = _ringingCallFrom(arguments);
        if (call != null) _systemRingingController.add(call);
        if (_capabilities.voipRing) {
          final ring = NativeRing.tryParse(arguments);
          if (ring != null) _nativeRingController.add(ring);
        }
      case 'audioRouteChanged':
        if (arguments is Map) _audioRouteController.add(arguments);
    }
  }

  String? _callIdFrom(Object? arguments) {
    final callId = arguments is Map ? arguments['callId'] : null;
    return callId is String ? callId : null;
  }

  Future<void> takeQueuedNativeCalls() async {
    final List<Object?>? queued;
    try {
      queued = await _channel.invokeListMethod<Object?>('takeCallEvents');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    for (final event in queued ?? const <Object?>[]) {
      if (event is! Map) continue;
      final method = event['method'];
      if (method is String) _handleNativeCall(method, event['arguments']);
    }
  }

  void _deliverNativeCallAction(
    CallNotificationAction action,
    Object? arguments,
  ) {
    final call = _ringingCallFrom(arguments);
    if (call == null) return;
    final response = CallNotificationResponse(action: action, call: call);
    if (_actionController.hasListener) {
      _actionController.add(response);
    } else {
      _pendingNativeCallAction = response;
    }
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
    bool includeMessageActions = false,
    Uint8List? senderAvatar,
    bool placeholder = false,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
    PushTiming? timing,
  }) async {
    await initialize(claimDeclinePort: false);
    timing?.mark('init');
    await _rooms.run(
      content.roomId,
      () => _showMessageInRoom(
        content,
        includeMessageActions: includeMessageActions,
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
    required bool includeMessageActions,
    required Uint8List? senderAvatar,
    required bool placeholder,
    required bool refine,
    required String? imageUri,
    required String? imageMimeType,
    required PushTiming? timing,
  }) async {
    final roomId = content.roomId;
    final title = content.title;
    final eventId = content.eventId;
    final senderAvatarUrl = content.senderAvatarUrl;
    final stored = await _withStore(
      (prefs) => (
        alreadyShown: eventId != null && wasEventNotified(prefs, eventId),
        placeholderDealtWith:
            eventId != null && wasPlaceholderShown(prefs, eventId),
        lines: readNotificationThread(prefs, roomId)?.lines,
        sound: readNotificationSoundSettings(prefs),
      ),
    );
    if (eventId != null && !refine && (stored?.alreadyShown ?? false)) {
      debugPrint('zuno/notifications: $eventId already shown, skipping');
      await _retractPushNoticeInRoom(roomId, eventId);
      return;
    }
    final noticed = !refine && await _takeNoticeFor(roomId, eventId);
    timing?.mark('prefs');
    final notificationId = messageNotificationIdFor(roomId);
    final showing = (await _activeNotifications()).any(
      (n) => n.id == notificationId,
    );
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
      title: title,
      isGroupChat: !content.isDirectChat,
      lines: placed,
    );
    final latest = placed.last;
    final newest = identical(latest, line);
    await _postThread(
      thread,
      alert: plan.alert,
      body: newest ? content.body : _summaryOf(thread, latest),
      eventId: newest ? eventId : latest.eventId,
      includeMessageActions: includeMessageActions,
      unreadCount: content.unreadCount,
      freshAvatar: senderAvatar == null
          ? null
          : (senderId: line.senderId, bytes: senderAvatar),
      shortcut: !placeholder && !refine,
      timing: timing,
    );
    await _withStore((prefs) async {
      await writeNotificationThread(prefs, thread);
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

  Future<void> retractPlaceholder(String roomId, String eventId) =>
      _rooms.run(roomId, () async {
        final thread = await _withStore(
          (prefs) => readNotificationThread(prefs, roomId),
        );
        if (thread == null) return;
        final kept = thread.lines
            .where((l) => !(l.placeholder && l.eventId == eventId))
            .toList();
        if (kept.length == thread.lines.length) return;
        if (kept.isEmpty) {
          await _cancelInRoom(roomId);
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
          body: _summaryOf(remaining, last),
          eventId: last.eventId,
          includeMessageActions: true,
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
    } catch (e) {
      debugPrint('zuno/notifications: notification store step failed ($e)');
      return null;
    }
  });

  Future<SharedPreferences?> _reloadedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs;
    } catch (_) {
      return null;
    }
  }

  Future<List<ActiveNotification>> _activeNotifications() async {
    try {
      return await _plugin.getActiveNotifications();
    } catch (_) {
      return const [];
    }
  }

  bool _isMessageNotification(ActiveNotification notification) =>
      _messageChannelIds.contains(notification.channelId) ||
      _decodePayload(notification.payload)?['type'] == 'message';

  Future<void> _postThread(
    NotificationThread thread, {
    required MessageAlert alert,
    required String body,
    required String? eventId,
    required bool includeMessageActions,
    required int? unreadCount,
    required ({String senderId, Uint8List bytes})? freshAvatar,
    required bool shortcut,
    required PushTiming? timing,
  }) async {
    final roomId = thread.roomId;
    final quiet = thread.lines.isNotEmpty && thread.lines.every((l) => l.quiet);
    final (channelId, channelName) = switch ((quiet, thread.isGroupChat)) {
      (true, _) => (_quietMessagesChannelId, 'Quiet messages'),
      (false, true) => (_groupMessagesChannelId, 'Room messages'),
      (false, false) => (messagesChannelId, 'Chat messages'),
    };
    final avatars = await _avatarsFor(thread, fresh: freshAvatar);
    timing?.mark('avatars');
    final latestLine = thread.lines.isEmpty ? null : thread.lines.last;
    final largeIcon = thread.isGroupChat || latestLine == null
        ? null
        : avatars[latestLine.senderId];
    if (shortcut) {
      await _pushConversationShortcut(thread, avatar: largeIcon);
      timing?.mark('shortcut');
    }
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
    final interrupts = !quiet && alert != MessageAlert.silentUpdate;
    final playsTone = interrupts && alert == MessageAlert.tone;
    final preview = _capabilities.nseNotifications
        ? await currentNotificationPreview(capabilities: _capabilities)
        : null;
    final hidden = preview == NotificationPreview.nothing;
    final messageActionsAllowed =
        !_capabilities.nativeNotificationActions ||
        (preview ?? NotificationPreview.full) == NotificationPreview.full;
    final threadIdentifier = switch (preview) {
      null => roomId,
      NotificationPreview.nothing => previewThread,
      _ => await _threadIds.tokenFor(roomId) ?? previewThread,
    };
    await _plugin.show(
      id: messageNotificationIdFor(roomId),
      title: hidden ? previewNothingTitle : thread.title,
      body: hidden ? previewHiddenText : body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          category: AndroidNotificationCategory.message,
          importance: quiet ? Importance.low : Importance.high,
          priority: quiet ? Priority.low : Priority.high,
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
        iOS: DarwinNotificationDetails(
          threadIdentifier: threadIdentifier,
          categoryIdentifier: darwinMessageCategory(
            includeMessageActions:
                includeMessageActions && messageActionsAllowed,
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
        'type': 'message',
        'roomId': roomId,
        'eventId': ?eventId,
      }),
    );
    timing?.mark('show');
  }

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
    } catch (e) {
      debugPrint('zuno/notifications: conversation shortcut skipped ($e)');
    }
  }

  Future<void> showNewDevice({
    required String deviceId,
    required String title,
    required String body,
  }) async {
    await initialize(claimDeclinePort: false);
    await _plugin.show(
      id: _newDeviceNotificationId(deviceId),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _securityChannelId,
          'New sign-ins',
          channelDescription: 'A new device signed in to your account',
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

  Future<void> cancelMessageNotification(String roomId) =>
      _rooms.run(roomId, () => _cancelInRoom(roomId));

  Future<void> _cancelInRoom(String roomId) async {
    await _plugin.cancel(id: messageNotificationIdFor(roomId));
    await _withStore((prefs) => clearNotificationThread(prefs, roomId));
  }

  Future<bool> takePushNotice(String roomId, String eventId) async {
    if (!_capabilities.instantPushNotices) return false;
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

  Future<void> retractPushNotice(String roomId, String eventId) =>
      _rooms.run(roomId, () => _retractPushNoticeInRoom(roomId, eventId));

  Future<void> _retractPushNoticeInRoom(String roomId, String eventId) async {
    if (!await takePushNotice(roomId, eventId)) return;
    debugPrint('zuno/notifications: cancelling the instant notice for $roomId');
    await _cancelInRoom(roomId);
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
    _quietMessagesChannelId,
  };

  Future<void> cancelAllMessageNotifications() async {
    await initialize(claimDeclinePort: false);
    for (final notification in await _activeNotifications()) {
      final id = notification.id;
      if (id == null) continue;
      if (!_isMessageNotification(notification)) continue;
      await _plugin.cancel(id: id);
    }
    await _withStore(clearAllNotificationThreads);
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
    final pending = _pendingNativeCallAction;
    if (pending != null) {
      _pendingNativeCallAction = null;
      return pending;
    }
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details?.notificationResponse;
    return callNotificationResponseFrom(
      actionId: response?.actionId,
      payload: response?.payload,
    );
  }

  Future<void> setShowOverLockscreen(bool show) =>
      _capabilities.lockScreenCallUi
      ? _invoke('setShowOverLockscreen', {'show': show})
      : Future.value();

  Future<void> setProximityScreenOff(bool enabled) =>
      _invoke('setProximityScreenOff', {'enabled': enabled});

  Future<void> setPictureInPicture({
    required bool eligible,
    required int aspectWidth,
    required int aspectHeight,
  }) => _capabilities.pictureInPicture
      ? _invoke('setPictureInPicture', {
          'eligible': eligible,
          'aspectWidth': aspectWidth,
          'aspectHeight': aspectHeight,
        })
      : Future.value();

  Future<bool> canUseFullScreenIntent() async =>
      await fullScreenIntentAllowedOrNull() ?? true;

  Future<bool?> fullScreenIntentAllowedOrNull() =>
      _capabilities.fullScreenIntent
      ? _invoke<bool>('canUseFullScreenIntent')
      : Future.value();

  Future<void> openFullScreenIntentSettings() => _capabilities.fullScreenIntent
      ? _invoke('openFullScreenIntentSettings')
      : Future.value();

  Future<List<SilencedChannel>> silencedChannels() async {
    try {
      return silencedMessageChannels(
        await _android?.getNotificationChannels() ?? const [],
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> openNotificationSettings() =>
      _invoke('openNotificationSettings');

  Future<void> openChannelSettings(String channelId) =>
      _invoke('openChannelSettings', {'channelId': channelId});

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}
