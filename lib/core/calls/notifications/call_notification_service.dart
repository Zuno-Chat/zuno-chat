import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show NotificationResponse;

import '../../errors/caught_errors.dart';
import '../../notifications/local_notifications.dart';
import '../../platform/platform_capabilities.dart';
import '../platform/native_ring.dart';

const _channel = MethodChannel('zuno/calls');

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
  return ringingCallFrom(decoded);
}

RingingCallInfo? ringingCallFrom(Object? value) {
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

class CallNotificationService {
  @visibleForTesting
  CallNotificationService({
    PlatformCapabilities? capabilities,
    LocalNotifications? notifications,
  }) : _injectedCapabilities = capabilities,
       _injectedNotifications = notifications;
  static final instance = CallNotificationService();

  final PlatformCapabilities? _injectedCapabilities;
  final LocalNotifications? _injectedNotifications;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  LocalNotifications get _notifications =>
      _injectedNotifications ?? LocalNotifications.instance;

  bool _ready = false;
  Future<void>? _setup;

  late final StreamController<CallNotificationResponse> _actionController =
      StreamController.broadcast(
        onListen: () =>
            _responses = _notifications.onResponse.listen(_onResponse),
        onCancel: () => _responses?.cancel(),
      );
  StreamSubscription<NotificationResponse>? _responses;
  final _hangUpController = StreamController<String?>.broadcast();
  final _openCallScreenController = StreamController<void>.broadcast();
  final _systemMuteController = StreamController<SystemMute>.broadcast();
  final _ringEndedController = StreamController<RingingCallInfo>.broadcast();
  final _systemCallFailedController = StreamController<String>.broadcast();
  final _systemRingingController =
      StreamController<RingingCallInfo>.broadcast();
  final _nativeRingController = StreamController<NativeRing>.broadcast();
  final _audioRouteController =
      StreamController<Map<Object?, Object?>>.broadcast();
  final inPictureInPicture = ValueNotifier<bool>(false);
  final pictureInPictureCamera = ValueNotifier<bool>(false);

  Stream<CallNotificationResponse> get onAction => _actionController.stream;
  Stream<String?> get onHangUp => _hangUpController.stream;
  Stream<void> get onOpenCallScreen => _openCallScreenController.stream;
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

  void _onResponse(NotificationResponse response) {
    final call = callNotificationResponseFrom(
      actionId: response.actionId,
      payload: response.payload,
    );
    if (call != null) _actionController.add(call);
  }

  Future<void> initialize({bool claimLiveRoutes = true}) async {
    if (claimLiveRoutes) _notifications.claimLiveRoutes();
    if (_ready) return;
    final setup = _setup ??= _setUp();
    try {
      await setup;
    } finally {
      if (identical(_setup, setup)) _setup = null;
    }
  }

  Future<void> _setUp() async {
    _channel.setMethodCallHandler((call) async {
      _handleNativeCall(call.method, call.arguments);
      return null;
    });
    if (_capabilities.callKit) await _invoke<void>('resetSystemCalls');
    await _notifications.initialize();
    _ready = true;
  }

  CallNotificationResponse? _pendingNativeCallAction;

  void _handleNativeCall(String method, Object? arguments) {
    switch (method) {
      case 'hangUpCall':
        _hangUpController.add(_callIdFrom(arguments));
      case 'openCallScreen':
        _openCallScreenController.add(null);
      case 'pictureInPictureChanged':
        inPictureInPicture.value = arguments == true;
      case 'pictureInPictureCameraChanged':
        pictureInPictureCamera.value = arguments == true;
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
        final call = ringingCallFrom(arguments);
        if (call != null) _ringEndedController.add(call);
      case 'callFailed':
        final callId = _callIdFrom(arguments);
        if (callId != null) _systemCallFailedController.add(callId);
      case 'ringing':
        final call = ringingCallFrom(arguments);
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
    } on PlatformException catch (e, s) {
      reportCaught('take queued native calls', e, s);
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
    final call = ringingCallFrom(arguments);
    if (call == null) return;
    final response = CallNotificationResponse(action: action, call: call);
    if (_actionController.hasListener) {
      _actionController.add(response);
    } else {
      _pendingNativeCallAction = response;
    }
  }

  Future<CallNotificationResponse?>
  takeLaunchCallActionFromNotification() async {
    final pending = _pendingNativeCallAction;
    if (pending != null) {
      _pendingNativeCallAction = null;
      return pending;
    }
    final response = await _notifications.launchResponse();
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
    String? streamId,
    String? ownerTag,
  }) => _capabilities.pictureInPicture
      ? _invoke('setPictureInPicture', {
          'eligible': eligible,
          'aspectWidth': aspectWidth,
          'aspectHeight': aspectHeight,
          'streamId': ?streamId,
          'ownerTag': ?ownerTag,
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
