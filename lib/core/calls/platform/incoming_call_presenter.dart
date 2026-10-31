import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../async/serial_lock.dart';
import '../../errors/caught_errors.dart';
import '../../l10n/l10n.dart';
import '../../notifications/local_notifications.dart';
import '../../notifications/settings/notification_preview.dart';
import '../../notifications/settings/notification_sound_settings.dart';
import '../../platform/platform_capabilities.dart';
import '../notifications/call_notification_service.dart';
import 'system_ring.dart';

const _callStyleChannel = MethodChannel('zuno/call_style');
const _callsChannel = MethodChannel('zuno/calls');

enum RingOutcome { shown, filtered, unavailable }

enum RingEnd { remoteEnded, answeredElsewhere, declinedElsewhere, unanswered }

abstract interface class IncomingCallPresenter {
  Future<RingOutcome> showIncoming({
    required String name,
    String? caller,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
    bool waiting = false,
    Duration? ringFor,
  });

  Future<void> ringAloud(String callId);

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

class AndroidIncomingCallPresenter implements IncomingCallPresenter {
  const AndroidIncomingCallPresenter();

  static final _turns = SerialLock();

  CallNotificationService get _notifications =>
      CallNotificationService.instance;

  @override
  Future<RingOutcome> showIncoming({
    required String name,
    String? caller,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
    bool waiting = false,
    Duration? ringFor,
  }) => _turns.run(() async {
    LocalNotifications.instance.reclaimLiveRoutes();
    final sound = loadNotificationSoundSettings();
    final level = currentNotificationPreview();
    await _notifications.initialize(claimLiveRoutes: false);
    debugPrint(
      'zuno/push: posting ring for $callId '
      '(fullScreenIntentAllowed='
      '${await _notifications.fullScreenIntentAllowedOrNull()})',
    );
    final settings = await sound;
    final preview = await level;
    final l10n = deviceLocalizations();
    final hidden = preview == NotificationPreview.nothing;
    final kind = isVideo ? l10n.callsIncomingVideo : l10n.callsIncomingVoice;
    final answer = await _invoke<String>('showIncomingCallStyle', {
      'channelId': isGroupCall ? groupRingChannelId : ringChannelId,
      'name': preview.callName(name, l10n),
      'text': hidden ? kind : caller ?? kind,
      'callerId': callerId,
      'isVideo': isVideo,
      'roomId': roomId,
      'callId': callId,
      'avatarBytes': hidden ? null : avatarBytes,
      'ringtone': settings.ringtone,
      'vibrate':
          settings.callVibration && ambientCapabilities.vibrationPatterns,
      if (waiting) 'waitingText': l10n.callsRingWaitingHint,
      'ringMs': ?ringFor?.inMilliseconds,
    });
    switch (answer) {
      case 'shown':
        return RingOutcome.shown;
      case 'ringing':
        debugPrint('zuno/calls: $callId already rings, not ringing it again');
        return RingOutcome.shown;
      case 'rangHere':
        debugPrint('zuno/calls: $callId already rang here, not ringing again');
        return RingOutcome.filtered;
      case 'busy':
        debugPrint('zuno/calls: another call rings, not ringing $callId');
        return RingOutcome.filtered;
      default:
        debugPrint('zuno/calls: $callId could not be shown, not ringing it');
        return RingOutcome.unavailable;
    }
  });

  @override
  Future<void> ringAloud(String callId) => _turns.run(
    () => _invoke<void>('ringIncomingCallStyleAloud', {'callId': callId}),
  );

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) {
    if (callId != null) SystemRing.instance.clear(callId);
    return _turns.run(
      () => _invoke<void>('cancelIncomingCallStyle', {'callId': callId}),
    );
  }

  @override
  Future<RingingCallInfo?> activeRing() async {
    try {
      return ringingCallFrom(await _invoke<Object?>('activeRing'));
    } catch (e, s) {
      reportCaught('read the active ring', e, s);
      return null;
    }
  }

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
    required String name,
    String? caller,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
    bool waiting = false,
    Duration? ringFor,
  }) async => RingOutcome.unavailable;

  @override
  Future<void> ringAloud(String callId) async {}

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
    required String name,
    String? caller,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
    bool waiting = false,
    Duration? ringFor,
  }) async {
    SystemRing.instance.set(roomId: roomId, callId: callId);
    final outcome = await _report({
      'roomId': roomId,
      'callId': callId,
      'callerId': callerId,
      'name': name,
      'isVideo': isVideo,
    });
    if (outcome != RingOutcome.shown) SystemRing.instance.clear(callId);
    return outcome;
  }

  @override
  Future<void> ringAloud(String callId) async {}

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
    } on PlatformException catch (e, s) {
      reportCaught('callkit reportIncomingCall', e, s);
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
