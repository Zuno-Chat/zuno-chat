import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final player = NotificationSoundPlayer.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('vibration', () {
    const channel = MethodChannel('zuno/vibration');
    late List<MethodCall> calls;
    var hasVibrator = true;
    Object? vibrateError;

    setUp(() {
      calls = <MethodCall>[];
      hasVibrator = true;
      vibrateError = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'hasVibrator':
                return hasVibrator;
              case 'vibrate':
              case 'cancel':
                final error = vibrateError;
                if (error != null) throw error;
                return null;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('a platform without vibration patterns never buzzes for a message '
        'and makes no native call', () async {
      final ios = NotificationSoundPlayer(
        capabilities: capabilitiesFor(AppPlatform.ios),
      );

      await ios.vibrateForMessage();

      expect(calls, isEmpty);
    });

    group('prepareMessageNotification', () {
      const room = '!room:example.org';
      late List<String> logs;
      late DebugPrintCallback originalDebugPrint;
      var fakeNow = DateTime(2030);

      setUp(() {
        logs = <String>[];
        originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        fakeNow = fakeNow.add(const Duration(days: 1));
        player.now = () => fakeNow;
        SharedPreferences.setMockInitialValues({
          messageToneEnabledKey: true,
          messageVibrationEnabledKey: true,
        });
      });

      tearDown(() {
        debugPrint = originalDebugPrint;
        player.now = DateTime.now;
      });

      test('asks for the tone (the sound channel) when the tone setting is '
          'on', () async {
        expect(await player.prepareMessageNotification(roomId: room), (
          alert: MessageAlert.tone,
          vibrate: true,
        ));
      });

      test('asks for silence but still a buzz when only the tone setting is '
          'off', () async {
        SharedPreferences.setMockInitialValues({
          messageToneEnabledKey: false,
          messageVibrationEnabledKey: true,
        });

        expect(await player.prepareMessageNotification(roomId: room), (
          alert: MessageAlert.silent,
          vibrate: true,
        ));
      });

      test('follows settings the caller already read instead of reading '
          'them again', () async {
        expect(
          await player.prepareMessageNotification(
            roomId: room,
            settings: const NotificationSoundSettings(
              ringtone: true,
              callVibration: true,
              messageTone: false,
              messageVibration: false,
            ),
          ),
          (alert: MessageAlert.silent, vibrate: false),
        );
      });

      test('preparing never buzzes itself; the buzz is a separate step so it '
          'can follow the post', () async {
        await player.prepareMessageNotification(roomId: room);

        expect(calls.map((c) => c.method), isNot(contains('vibrate')));
      });

      test('vibrateForMessage buzzes with the message pattern tagged as a '
          'notification, not an alarm', () async {
        await player.vibrateForMessage();

        final vibrate = calls.singleWhere((c) => c.method == 'vibrate');
        expect(vibrate.arguments['pattern'], messageVibrationPattern);
        expect(vibrate.arguments['repeat'], -1);
        expect(vibrate.arguments['usage'], 'notification');
      });

      test(
        'no vibrator on the device is logged as that, not as a failure',
        () async {
          hasVibrator = false;

          await player.vibrateForMessage();

          expect(calls.map((c) => c.method), isNot(contains('vibrate')));
          expect(
            logs,
            contains('zuno/sound: message vibration skipped, no vibrator'),
          );
          expect(
            logs.any((m) => m.contains('message vibration failed')),
            isFalse,
          );
        },
      );

      test('a failing vibration platform names what failed', () async {
        vibrateError = PlatformException(code: 'muted');

        await player.vibrateForMessage();

        expect(
          logs,
          contains(
            predicate<String>(
              (m) => m.startsWith('zuno/sound: message vibration failed:'),
            ),
          ),
        );
      });

      test('a failing vibration platform is swallowed, never thrown at the '
          'poster', () async {
        vibrateError = PlatformException(code: 'muted');

        await expectLater(player.vibrateForMessage(), completes);
      });

      test('both settings off is logged as a deliberate skip, and is '
          'silent', () async {
        SharedPreferences.setMockInitialValues({
          messageToneEnabledKey: false,
          messageVibrationEnabledKey: false,
        });

        expect(await player.prepareMessageNotification(roomId: room), (
          alert: MessageAlert.silent,
          vibrate: false,
        ));
        expect(calls, isEmpty);
        expect(
          logs,
          contains('zuno/sound: message tone skipped, both settings off'),
        );
      });

      test('a second call within the rate limit for the same room is logged '
          'as a skip and is a silent update: no buzz, and the notification '
          'stays on the sound channel so the tone is not cut off', () async {
        await player.prepareMessageNotification(roomId: room);
        logs.clear();
        calls.clear();

        final result = await player.prepareMessageNotification(roomId: room);

        expect(result, (alert: MessageAlert.silentUpdate, vibrate: false));
        expect(calls, isEmpty);
        expect(
          logs,
          contains('zuno/sound: message tone skipped, rate-limited'),
        );
      });

      test('a second call within the rate limit for another room is plain '
          'silent', () async {
        await player.prepareMessageNotification(roomId: room);
        calls.clear();

        final result = await player.prepareMessageNotification(
          roomId: '!other:example.org',
        );

        expect(result, (alert: MessageAlert.silent, vibrate: false));
        expect(calls, isEmpty);
      });

      test('with the tone setting off there is nothing to keep playing, so '
          'a same-room burst is plain silent', () async {
        SharedPreferences.setMockInitialValues({
          messageToneEnabledKey: false,
          messageVibrationEnabledKey: true,
        });
        await player.prepareMessageNotification(roomId: room);

        expect(await player.prepareMessageNotification(roomId: room), (
          alert: MessageAlert.silent,
          vibrate: false,
        ));
      });
    });
  });
}
