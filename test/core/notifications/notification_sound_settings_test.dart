import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
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

    test('throws on a stored value of the wrong type', () async {
      final prefs = await prefsWith({ringtoneEnabledKey: 'yes'});

      expect(
        () => readNotificationSoundSettings(prefs),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('loadNotificationSoundSettings', () {
    test('reads back what was stored, reload()d fresh', () async {
      await prefsWith({messageToneEnabledKey: false});

      final settings = await loadNotificationSoundSettings();

      expect(settings.messageTone, isFalse);
      expect(settings.messageVibration, isTrue);
    });
  });

  group('messageAlertFor', () {
    final now = DateTime(2026, 9, 4, 12);
    const room = '!a:example.org';

    test('plays the tone when nothing has played yet', () {
      expect(
        messageAlertFor(
          roomId: room,
          lastToneRoomId: null,
          lastToneAt: null,
          now: now,
        ),
        MessageAlert.tone,
      );
    });

    test('plays the tone again once the interval has passed', () {
      expect(
        messageAlertFor(
          roomId: room,
          lastToneRoomId: room,
          lastToneAt: now.subtract(minMessageToneInterval),
          now: now,
        ),
        MessageAlert.tone,
      );
    });

    test('a second message in the same room moments later is a silent '
        'update, so the tone still playing is not cut off', () {
      expect(
        messageAlertFor(
          roomId: room,
          lastToneRoomId: room,
          lastToneAt: now.subtract(const Duration(milliseconds: 300)),
          now: now,
        ),
        MessageAlert.silentUpdate,
      );
    });

    test('a message in another room moments later is plain silent', () {
      expect(
        messageAlertFor(
          roomId: '!b:example.org',
          lastToneRoomId: room,
          lastToneAt: now.subtract(const Duration(milliseconds: 300)),
          now: now,
        ),
        MessageAlert.silent,
      );
    });

    test('a burst in the same room arriving in the same instant is a silent '
        'update', () {
      expect(
        messageAlertFor(
          roomId: room,
          lastToneRoomId: room,
          lastToneAt: now,
          now: now,
        ),
        MessageAlert.silentUpdate,
      );
    });
  });

  group('audio focus', () {
    test('nothing posted from the background asks for audio focus', () {
      expect(
        ringAudioContext.android.audioFocus,
        AndroidAudioFocus.none,
        reason: 'a focus request the OS denies costs the sound entirely',
      );
      expect(
        ringAudioContext.android.usageType,
        AndroidUsageType.notificationRingtone,
      );
    });

    test('no sound played during a call carries an audio context', () {
      expect(
        ringAudioContext.android.audioMode,
        AndroidAudioMode.normal,
        reason: 'the ring only ever plays outside a call, where normal is right',
      );
    });
  });

  group('vibration patterns', () {
    test('the call pattern starts with a zero wait and repeats cleanly', () {
      expect(callVibrationPattern.first, 0);
      expect(callVibrationPattern.length.isOdd, isTrue);
    });

    test('the message pattern is a double buzz starting with a zero wait',
        () {
      expect(messageVibrationPattern, [0, 300, 150, 300]);
      expect(messageVibrationPattern.first, 0);
    });
  });
}
