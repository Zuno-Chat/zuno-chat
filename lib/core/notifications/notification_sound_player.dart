import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

import '../platform/platform_capabilities.dart';
import 'notification_sound_settings.dart';

const _vibrationChannel = MethodChannel('zuno/vibration');

class NotificationSoundPlayer {
  @visibleForTesting
  NotificationSoundPlayer({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = NotificationSoundPlayer();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  DateTime? _lastMessageToneAt;
  String? _lastMessageToneRoomId;

  DateTime Function() now = DateTime.now;

  void recordNoticeAlert(String roomId) {
    _lastMessageToneAt = now();
    _lastMessageToneRoomId = roomId;
  }

  Future<MessageAlertPlan> prepareMessageNotification({
    required String roomId,
    NotificationSoundSettings? settings,
  }) async {
    settings ??= await loadNotificationSoundSettings();
    if (!settings.messageTone && !settings.messageVibration) {
      if (kDebugMode) {
        debugPrint('zuno/sound: message tone skipped, both settings off');
      }
      return (alert: MessageAlert.silent, vibrate: false);
    }
    final alert = messageAlertFor(
      roomId: roomId,
      lastToneRoomId: _lastMessageToneRoomId,
      lastToneAt: _lastMessageToneAt,
      now: now(),
    );
    if (alert != MessageAlert.tone) {
      if (kDebugMode) {
        debugPrint('zuno/sound: message tone skipped, rate-limited');
      }
      return (
        alert: settings.messageTone ? alert : MessageAlert.silent,
        vibrate: false,
      );
    }
    _lastMessageToneAt = now();
    _lastMessageToneRoomId = roomId;
    return (
      alert: settings.messageTone ? MessageAlert.tone : MessageAlert.silent,
      vibrate: settings.messageVibration,
    );
  }

  Future<void> vibrateForMessage() async {
    if (!_capabilities.vibrationPatterns) return;
    try {
      final hasVibrator =
          await _vibrationChannel.invokeMethod<bool>('hasVibrator') ?? false;
      if (!hasVibrator) {
        if (kDebugMode) {
          debugPrint('zuno/sound: message vibration skipped, no vibrator');
        }
        return;
      }
      await _vibrationChannel.invokeMethod<void>('vibrate', {
        'pattern': messageVibrationPattern,
        'repeat': -1,
        'usage': 'notification',
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('zuno/sound: message vibration failed: $e');
      }
    }
  }
}
