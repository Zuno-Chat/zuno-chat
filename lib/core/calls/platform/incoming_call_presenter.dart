import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notifications/notification_sound_player.dart';
import '../../platform/platform_capabilities.dart';
import '../notifications/call_notification_service.dart';
import '../notifications/ringing_call_store.dart';

const _callStyleChannel = MethodChannel('zuno/call_style');
const _ringNotificationId = 4002;

abstract interface class IncomingCallPresenter {
  Future<void> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
  });

  Future<void> cancelIncoming();

  Future<RingingCallInfo?> activeRing();
}

IncomingCallPresenter incomingCallPresenterFor(
  PlatformCapabilities capabilities,
) => capabilities.fullScreenIntent
    ? const AndroidIncomingCallPresenter()
    : const NoopIncomingCallPresenter();

final incomingCallPresenterProvider = Provider<IncomingCallPresenter>(
  (ref) => incomingCallPresenterFor(ref.watch(platformCapabilitiesProvider)),
);

class AndroidIncomingCallPresenter implements IncomingCallPresenter {
  const AndroidIncomingCallPresenter();

  CallNotificationService get _notifications =>
      CallNotificationService.instance;

  @override
  Future<void> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
  }) async {
    await _notifications.initialize();
    debugPrint(
      'zuno/push: posting ring for $callId '
      '(fullScreenIntentAllowed='
      '${await _notifications.fullScreenIntentAllowedOrNull()})',
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
      'channelId': isGroupCall ? groupRingChannelId : ringChannelId,
      'title': isVideo ? 'Incoming video call' : 'Incoming voice call',
      'callerName': callerName,
      'callerId': callerId,
      'isVideo': isVideo,
      'roomId': roomId,
      'callId': callId,
      'avatarBytes': avatarBytes,
    });
  }

  @override
  Future<void> cancelIncoming() async {
    await NotificationSoundPlayer.instance.stopIncomingRing();
    try {
      await clearRingingCall(await SharedPreferences.getInstance());
    } catch (_) {}
    await _invoke('cancelIncomingCallStyle');
  }

  @override
  Future<RingingCallInfo?> activeRing() async {
    await _notifications.initialize();
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

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _callStyleChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}

class NoopIncomingCallPresenter implements IncomingCallPresenter {
  const NoopIncomingCallPresenter();

  @override
  Future<void> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
  }) async {}

  @override
  Future<void> cancelIncoming() async {}

  @override
  Future<RingingCallInfo?> activeRing() async => null;
}
