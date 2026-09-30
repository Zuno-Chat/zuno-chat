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
import 'system_ring.dart';

const _callStyleChannel = MethodChannel('zuno/call_style');
const _callsChannel = MethodChannel('zuno/calls');
const _ringNotificationId = 4002;

enum RingOutcome { shown, filtered, unavailable }

enum RingEnd { remoteEnded, answeredElsewhere, declinedElsewhere, unanswered }

abstract interface class IncomingCallPresenter {
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
  });

  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  });

  Future<RingingCallInfo?> activeRing();
}

IncomingCallPresenter incomingCallPresenterFor(
  PlatformCapabilities capabilities,
) {
  if (capabilities.callKit) return const CallKitIncomingCallPresenter();
  if (capabilities.nativeIncomingRingUi) {
    return const AndroidIncomingCallPresenter();
  }
  return const NoopIncomingCallPresenter();
}

final incomingCallPresenterProvider = Provider<IncomingCallPresenter>(
  (ref) => incomingCallPresenterFor(ref.watch(platformCapabilitiesProvider)),
);

abstract class RememberingIncomingCallPresenter
    implements IncomingCallPresenter {
  const RememberingIncomingCallPresenter();

  Future<void> presentIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    required bool isGroupCall,
    Uint8List? avatarBytes,
  });

  Future<void> dismissIncoming();

  @override
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
  }) async {
    try {
      await saveRingingCall(await SharedPreferences.getInstance(), (
        roomId: roomId,
        callId: callId,
        callerId: callerId,
        isVideo: isVideo,
      ));
    } catch (_) {}
    await presentIncoming(
      callerName: callerName,
      callerId: callerId,
      isVideo: isVideo,
      roomId: roomId,
      callId: callId,
      isGroupCall: isGroupCall,
      avatarBytes: avatarBytes,
    );
    return RingOutcome.shown;
  }

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {
    if (callId != null) SystemRing.instance.clear(callId);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (callId != null) {
        await prefs.reload();
        final ringing = readRingingCall(prefs);
        if (ringing != null && ringing.callId != callId) return;
      }
      await clearRingingCall(prefs);
    } catch (_) {}
    await dismissIncoming();
  }

  Future<RingingCallInfo?> rememberedRing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return readRingingCall(prefs);
  }
}

class AndroidIncomingCallPresenter extends RememberingIncomingCallPresenter {
  const AndroidIncomingCallPresenter();

  CallNotificationService get _notifications =>
      CallNotificationService.instance;

  @override
  Future<void> presentIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    required bool isGroupCall,
    Uint8List? avatarBytes,
  }) async {
    await _notifications.initialize();
    debugPrint(
      'zuno/push: posting ring for $callId '
      '(fullScreenIntentAllowed='
      '${await _notifications.fullScreenIntentAllowedOrNull()})',
    );
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
  Future<void> dismissIncoming() async {
    await NotificationSoundPlayer.instance.stopIncomingRing();
    await _invoke('cancelIncomingCallStyle');
  }

  @override
  Future<RingingCallInfo?> activeRing() async {
    await _notifications.initialize();
    try {
      final active = await _android?.getActiveNotifications();
      final showing = active?.any((n) => n.id == _ringNotificationId) ?? false;
      if (!showing) return null;
      return await rememberedRing();
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
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
  }) async => RingOutcome.unavailable;

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {}

  @override
  Future<RingingCallInfo?> activeRing() async => null;
}

class CallKitIncomingCallPresenter implements IncomingCallPresenter {
  const CallKitIncomingCallPresenter();

  @override
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
  }) async {
    SystemRing.instance.set(roomId: roomId, callId: callId);
    final outcome = await _report({
      'roomId': roomId,
      'callId': callId,
      'callerId': callerId,
      'name': isGroupCall ? roomName ?? callerName : callerName,
      'isVideo': isVideo,
    });
    if (outcome != RingOutcome.shown) SystemRing.instance.clear(callId);
    return outcome;
  }

  Future<RingOutcome> _report(Map<String, Object?> ring) async {
    try {
      return switch (await _callsChannel.invokeMethod<String>(
        'reportIncomingCall',
        ring,
      )) {
        'shown' => RingOutcome.shown,
        'filtered' => RingOutcome.filtered,
        _ => RingOutcome.unavailable,
      };
    } on MissingPluginException {
      return RingOutcome.unavailable;
    } on PlatformException catch (e) {
      debugPrint('zuno/callkit: ring for ${ring['callId']} not reported: $e');
      return RingOutcome.unavailable;
    }
  }

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {
    if (roomId == null || callId == null) return;
    SystemRing.instance.clear(callId);
    try {
      await _callsChannel.invokeMethod<void>('endIncomingCall', {
        'roomId': roomId,
        'callId': callId,
        'reason': end.name,
      });
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<RingingCallInfo?> activeRing() async => null;
}
