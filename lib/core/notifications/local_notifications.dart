import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart' show Client;

import '../async/live_isolate_route.dart';
import '../calls/notifications/call_decline_action.dart';
import '../errors/caught_errors.dart';
import '../errors/device_log.dart';
import '../l10n/l10n.dart';
import '../matrix/matrix_client_provider.dart';
import '../network/app_http_overrides.dart';
import '../platform/platform_capabilities.dart';
import 'actions/message_notification_action.dart';

const ringChannelId = 'calls_ringing';
const groupRingChannelId = 'calls_ringing_group';
const messagesChannelId = 'direct_messages';
const groupMessagesChannelId = 'group_messages';
const quietMessagesChannelId = 'quiet_messages';
const securityChannelId = 'security';
const _callsGroupId = 'calls_group';
const _chatsGroupId = 'chats_group';
const _accountGroupId = 'account_group';

const ringChannelIds = {ringChannelId, groupRingChannelId};
const alertingMessageChannelIds = {messagesChannelId, groupMessagesChannelId};
const messageChannelIds = {
  messagesChannelId,
  groupMessagesChannelId,
  quietMessagesChannelId,
};

const messagePayloadType = 'message';
const securityAlertPayloadType = 'newDevice';

const _markReadCategoryId = 'message';
const _replyOnlyCategoryId = 'reply';

String? darwinMessageCategory({
  required bool includeMessageActions,
  required String? eventId,
}) => switch ((includeMessageActions, eventId)) {
  (false, _) => null,
  (true, null) => _replyOnlyCategoryId,
  (true, _) => _markReadCategoryId,
};

Map<String, Object?>? decodeNotificationPayload(String? payload) {
  if (payload == null) return null;
  try {
    return jsonDecode(payload) as Map<String, Object?>;
  } on FormatException {
    return null;
  }
}

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
void _handleBackgroundNotificationResponse(NotificationResponse response) =>
    runWithDeviceLogFloor(() => _handleBackgroundResponse(response));

void _handleBackgroundResponse(NotificationResponse response) {
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
  final decoded = decodeNotificationPayload(response.payload);
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
  await installAppHttpOverrides();
  return (await createMatrixClient(backgroundSync: false)).client;
}

class LocalNotifications {
  @visibleForTesting
  LocalNotifications({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = LocalNotifications();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  final plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _setup;

  final _responseController =
      StreamController<NotificationResponse>.broadcast();
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

  Stream<NotificationResponse> get onResponse => _responseController.stream;
  Stream<HeadlessCallDecline> get onHeadlessDecline =>
      _headlessDeclineController.stream;
  Stream<HandedMessageAction> get onMessageAction =>
      _messageActionController.stream;

  @visibleForTesting
  void onResponseForTest(NotificationResponse response) =>
      _responseController.add(response);

  @visibleForTesting
  void onHeadlessDeclineForTest(HeadlessCallDecline decline) =>
      _headlessDeclineController.add(decline);

  @visibleForTesting
  void onMessageActionForTest(HandedMessageAction action) =>
      _messageActionController.add(action);

  AndroidFlutterLocalNotificationsPlugin? get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> initialize() async {
    if (_ready) return;
    final setup = _setup ??= _setUp();
    try {
      await setup;
    } finally {
      if (identical(_setup, setup)) _setup = null;
    }
  }

  Future<void> _setUp() async {
    final l10n = deviceLocalizations();
    await plugin.initialize(
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
              : _messageCategories(l10n),
        ),
      ),
      onDidReceiveNotificationResponse: _responseController.add,
      onDidReceiveBackgroundNotificationResponse:
          _handleBackgroundNotificationResponse,
    );

    await _registerChannels(l10n);
    for (final channelId in _retiredChannelIds) {
      await android?.deleteNotificationChannel(channelId: channelId);
    }
    _ready = true;
  }

  Future<void> refreshChannelNames(AppLocalizations l10n) async {
    if (!_ready) return;
    await _registerChannels(l10n);
  }

  Future<void> _registerChannels(AppLocalizations l10n) async {
    final android = this.android;
    if (android == null) return;
    await android.createNotificationChannelGroup(
      AndroidNotificationChannelGroup(
        _callsGroupId,
        l10n.callsChannelGroupCalls,
      ),
    );
    await android.createNotificationChannelGroup(
      AndroidNotificationChannelGroup(
        _chatsGroupId,
        l10n.notificationsChannelGroupChats,
      ),
    );
    await android.createNotificationChannelGroup(
      AndroidNotificationChannelGroup(
        _accountGroupId,
        l10n.notificationsChannelGroupAccount,
      ),
    );
    for (final channel in _channels(l10n)) {
      await android.createNotificationChannel(channel);
    }
  }

  static List<DarwinNotificationCategory> _messageCategories(
    AppLocalizations l10n,
  ) {
    final replyAction = DarwinNotificationAction.text(
      'reply',
      l10n.commonReply,
      buttonTitle: l10n.commonSend,
      placeholder: l10n.commonMessageHint,
    );
    return [
      DarwinNotificationCategory(
        _markReadCategoryId,
        actions: [
          replyAction,
          DarwinNotificationAction.plain('mark_read', l10n.commonMarkAsRead),
        ],
      ),
      DarwinNotificationCategory(_replyOnlyCategoryId, actions: [replyAction]),
    ];
  }

  static const _retiredChannelIds = [
    'messages',
    'messages_group',
    'messages_sound_v1',
    'messages_group_sound_v1',
  ];

  static List<AndroidNotificationChannel> _channels(AppLocalizations l10n) => [
    AndroidNotificationChannel(
      ringChannelId,
      l10n.callsChannelIncomingCalls,
      description: l10n.callsChannelIncomingCallsDescription,
      importance: Importance.max,
      groupId: _callsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      messagesChannelId,
      l10n.notificationsChannelChatMessages,
      description: l10n.notificationsChannelChatMessagesDescription,
      importance: Importance.high,
      groupId: _chatsGroupId,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('message_tone'),
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      groupRingChannelId,
      l10n.callsChannelIncomingRoomCalls,
      description: l10n.callsChannelIncomingRoomCallsDescription,
      importance: Importance.max,
      groupId: _callsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      groupMessagesChannelId,
      l10n.notificationsChannelRoomMessages,
      description: l10n.notificationsChannelRoomMessagesDescription,
      importance: Importance.high,
      groupId: _chatsGroupId,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('message_tone'),
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      quietMessagesChannelId,
      l10n.notificationsChannelQuietMessages,
      description: l10n.notificationsChannelQuietMessagesDescription,
      importance: Importance.low,
      groupId: _chatsGroupId,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      securityChannelId,
      l10n.notificationsChannelSecurity,
      description: l10n.notificationsChannelSecurityDescription,
      importance: Importance.max,
      groupId: _accountGroupId,
    ),
  ];

  Future<List<ActiveNotification>> activeNotifications() async {
    try {
      return await plugin.getActiveNotifications();
    } catch (e, s) {
      reportCaught('read active notifications', e, s);
      return const [];
    }
  }

  Future<NotificationResponse?> launchResponse() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse;
  }

  bool _ownsLiveRoutes = false;
  ReceivePort? _declinePort;
  ReceivePort? _actionPort;
  final _heldDeclines = <HeadlessCallDecline>[];
  final _heldActions = <HandedMessageAction>[];

  void claimLiveRoutes() {
    if (_ownsLiveRoutes) return;
    _ownsLiveRoutes = true;
    reclaimLiveRoutes();
  }

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
}
