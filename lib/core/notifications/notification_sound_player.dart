import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

import 'notification_sound_settings.dart';

final ringAudioContext = AudioContext(
  android: AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.notificationRingtone,
    audioFocus: AndroidAudioFocus.none,
  ),
);

const _callsChannel = MethodChannel('zuno/calls');

const _vibrationChannel = MethodChannel('zuno/vibration');

@visibleForTesting
const ringStopPortName = 'zuno_ring_stop_port';

class NotificationSoundPlayer {
  NotificationSoundPlayer._();
  static final instance = NotificationSoundPlayer._();

  AudioPlayer? _ringPlayer;

  Timer? _ringSafetyTimer;
  ReceivePort? _ringStopPort;
  bool _ringbackPlaying = false;
  DateTime? _lastMessageToneAt;
  String? _lastMessageToneRoomId;

  DateTime Function() now = DateTime.now;

  Future<void> startIncomingRing() async {
    final settings = await loadNotificationSoundSettings();
    await stopIncomingRing();
    _claimRingStopPort();
    _ringSafetyTimer = Timer(maxRingDuration, () {
      unawaited(_stopIncomingRingHere());
    });
    if (settings.ringtone) {
      await _guard('ring tone', () async {
        final player = _ringPlayer ??= AudioPlayer();
        await player.setAudioContext(ringAudioContext);
        await player.setReleaseMode(ReleaseMode.loop);
        await player.play(AssetSource('sounds/ringtone.wav'));
      });
    }
    if (settings.callVibration) {
      await _guard('ring vibration', () async {
        if (!await _hasVibrator()) {
          if (kDebugMode) {
            debugPrint('zuno/sound: ring vibration skipped, no vibrator');
          }
          return;
        }
        await _vibrate(
          pattern: callVibrationPattern,
          repeat: 0,
          usage: 'ringtone',
        );
      });
    }
  }

  Future<void> stopIncomingRing() async {
    if (_ringStopPort == null) {
      IsolateNameServer.lookupPortByName(ringStopPortName)?.send(null);
    }
    await _stopIncomingRingHere();
  }

  Future<void> _stopIncomingRingHere() async {
    _releaseRingStopPort();
    _ringSafetyTimer?.cancel();
    _ringSafetyTimer = null;
    await _guard('ring stop', () => _ringPlayer?.stop() ?? Future.value());
    await _guard('vibration cancel', _cancelVibration);
  }

  @visibleForTesting
  bool get ownsIncomingRing => _ringStopPort != null;

  void _claimRingStopPort() {
    _releaseRingStopPort();
    final port = ReceivePort();
    _ringStopPort = port;
    IsolateNameServer.removePortNameMapping(ringStopPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, ringStopPortName);
    port.listen((_) => unawaited(_stopIncomingRingHere()));
  }

  void _releaseRingStopPort() {
    final port = _ringStopPort;
    if (port == null) return;
    _ringStopPort = null;
    if (IsolateNameServer.lookupPortByName(ringStopPortName) == port.sendPort) {
      IsolateNameServer.removePortNameMapping(ringStopPortName);
    }
    port.close();
  }

  Future<void> startRingback() async {
    if (_ringbackPlaying) return;
    final settings = await loadNotificationSoundSettings();
    if (!settings.ringtone) return;
    _ringbackPlaying = true;
    debugPrint('zuno/sound: ringback start');
    await _invokeCallChannel('startRingbackTone');
  }

  Future<void> stopRingback() async {
    if (!_ringbackPlaying) return;
    _ringbackPlaying = false;
    debugPrint('zuno/sound: ringback stop');
    await _invokeCallChannel('stopRingbackTone');
  }

  Future<void> restartRingbackForRouteChange() async {
    if (!_ringbackPlaying) return;
    await stopRingback();
    await startRingback();
  }

  @visibleForTesting
  bool get isRingbackPlaying => _ringbackPlaying;

  Future<MessageAlertPlan> prepareMessageNotification({
    required String roomId,
  }) async {
    final settings = await loadNotificationSoundSettings();
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

  Future<void> vibrateForMessage() => _guard('message vibration', () async {
    if (!await _hasVibrator()) {
      if (kDebugMode) {
        debugPrint('zuno/sound: message vibration skipped, no vibrator');
      }
      return;
    }
    await _vibrate(
      pattern: messageVibrationPattern,
      repeat: -1,
      usage: 'notification',
    );
  });

  Future<void> _invokeCallChannel(String method) async {
    try {
      await _callsChannel.invokeMethod<void>(method);
    } catch (_) {}
  }

  Future<bool> _hasVibrator() async {
    return await _vibrationChannel.invokeMethod<bool>('hasVibrator') ?? false;
  }

  Future<void> _vibrate({
    required List<int> pattern,
    required int repeat,
    required String usage,
  }) {
    return _vibrationChannel.invokeMethod<void>('vibrate', {
      'pattern': pattern,
      'repeat': repeat,
      'usage': usage,
    });
  }

  Future<void> _cancelVibration() {
    return _vibrationChannel.invokeMethod<void>('cancel');
  }

  Future<void> _guard(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('zuno/sound: $label failed: $e');
      }
    }
  }
}
