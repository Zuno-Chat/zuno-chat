import 'package:shared_preferences/shared_preferences.dart';

const ringtoneEnabledKey = 'settings.ringtone_enabled';
const callVibrationEnabledKey = 'settings.call_vibration_enabled';
const messageToneEnabledKey = 'settings.message_tone_enabled';
const messageVibrationEnabledKey = 'settings.message_vibration_enabled';

class NotificationSoundSettings {
  final bool ringtone;
  final bool callVibration;
  final bool messageTone;
  final bool messageVibration;

  const NotificationSoundSettings({
    required this.ringtone,
    required this.callVibration,
    required this.messageTone,
    required this.messageVibration,
  });

  static const defaults = NotificationSoundSettings(
    ringtone: true,
    callVibration: true,
    messageTone: true,
    messageVibration: true,
  );
}

Future<NotificationSoundSettings> loadNotificationSoundSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return readNotificationSoundSettings(prefs);
  } catch (_) {
    return NotificationSoundSettings.defaults;
  }
}

NotificationSoundSettings readNotificationSoundSettings(
  SharedPreferences prefs,
) {
  const fallback = NotificationSoundSettings.defaults;
  return NotificationSoundSettings(
    ringtone: prefs.getBool(ringtoneEnabledKey) ?? fallback.ringtone,
    callVibration:
        prefs.getBool(callVibrationEnabledKey) ?? fallback.callVibration,
    messageTone: prefs.getBool(messageToneEnabledKey) ?? fallback.messageTone,
    messageVibration:
        prefs.getBool(messageVibrationEnabledKey) ?? fallback.messageVibration,
  );
}

const callVibrationPattern = <int>[0, 800, 500, 800, 2000];

const messageVibrationPattern = <int>[0, 300, 150, 300];

const maxRingDuration = Duration(seconds: 60);

const minMessageToneInterval = Duration(seconds: 2);

enum MessageAlert { tone, silentUpdate, silent }

typedef MessageAlertPlan = ({MessageAlert alert, bool vibrate});

MessageAlert messageAlertFor({
  required String roomId,
  required String? lastToneRoomId,
  required DateTime? lastToneAt,
  required DateTime now,
}) {
  if (lastToneAt == null ||
      now.difference(lastToneAt) >= minMessageToneInterval) {
    return MessageAlert.tone;
  }
  return roomId == lastToneRoomId
      ? MessageAlert.silentUpdate
      : MessageAlert.silent;
}
