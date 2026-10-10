import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  group('readNotificationSoundSettings', () {
    test(
      'everything is on for a user who has never touched a toggle',
      () async {
        final settings = readNotificationSoundSettings(await prefsWith({}));

        expect(settings.ringtone, isTrue);
        expect(settings.callVibration, isTrue);
        expect(settings.messageTone, isTrue);
        expect(settings.messageVibration, isTrue);
      },
    );

    test('reads each stored value back', () async {
      final settings = readNotificationSoundSettings(
        await prefsWith({
          ringtoneEnabledKey: false,
          callVibrationEnabledKey: false,
          messageToneEnabledKey: false,
          messageVibrationEnabledKey: false,
        }),
      );

      expect(settings.ringtone, isFalse);
      expect(settings.callVibration, isFalse);
      expect(settings.messageTone, isFalse);
      expect(settings.messageVibration, isFalse);
    });

    test('falls back per key, not as a whole', () async {
      final settings = readNotificationSoundSettings(
        await prefsWith({messageToneEnabledKey: false}),
      );

      expect(settings.messageTone, isFalse);
      expect(settings.ringtone, isTrue);
      expect(settings.callVibration, isTrue);
      expect(settings.messageVibration, isTrue);
    });
  });

  group('loadNotificationSoundSettings', () {
    test('reads back what was stored, reload()d fresh', () async {
      await prefsWith({messageToneEnabledKey: false});

      final settings = await loadNotificationSoundSettings();

      expect(settings.messageTone, isFalse);
      expect(settings.messageVibration, isTrue);
    });

    test('falls back to every default when a stored value has the wrong '
        'type', () async {
      await prefsWith({
        ringtoneEnabledKey: 'yes',
        messageToneEnabledKey: false,
      });

      expect(
        await loadNotificationSoundSettings(),
        same(NotificationSoundSettings.defaults),
      );
    });
  });

  group('messageAlertFor', () {
    final now = DateTime(2026, 9, 4, 12);
    const room = '!a:example.org';
    const moments = Duration(milliseconds: 300);

    for (final (name, roomId, lastToneRoomId, lastToneAt, expected) in [
      (
        'plays the tone when nothing has played yet',
        room,
        null,
        null,
        MessageAlert.tone,
      ),
      (
        'plays the tone again once the interval has passed',
        room,
        room,
        now.subtract(minMessageToneInterval),
        MessageAlert.tone,
      ),
      (
        'a second message in the same room moments later is a silent '
            'update, so the tone still playing is not cut off',
        room,
        room,
        now.subtract(moments),
        MessageAlert.silentUpdate,
      ),
      (
        'a message in another room moments later is plain silent',
        '!b:example.org',
        room,
        now.subtract(moments),
        MessageAlert.silent,
      ),
      (
        'a burst in the same room arriving in the same instant is a silent '
            'update',
        room,
        room,
        now,
        MessageAlert.silentUpdate,
      ),
    ]) {
      test(name, () {
        expect(
          messageAlertFor(
            roomId: roomId,
            lastToneRoomId: lastToneRoomId,
            lastToneAt: lastToneAt,
            now: now,
          ),
          expected,
        );
      });
    }
  });
}
