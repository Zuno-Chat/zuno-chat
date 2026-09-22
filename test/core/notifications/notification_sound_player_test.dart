import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final player = NotificationSoundPlayer.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the ringtone preference off leaves no ringback to move', () async {
    SharedPreferences.setMockInitialValues({ringtoneEnabledKey: false});

    await player.startRingback();

    expect(player.isRingbackPlaying, isFalse);
    await player.restartRingbackForRouteChange();
    expect(player.isRingbackPlaying, isFalse);
  });

  test('the ringback starts and stops with the preference on', () async {
    await player.startRingback();
    expect(player.isRingbackPlaying, isTrue);

    await player.startRingback();
    expect(player.isRingbackPlaying, isTrue);

    await player.stopRingback();
    expect(player.isRingbackPlaying, isFalse);
  });

  test('a route change restarts a ringing tone', () async {
    await player.startRingback();

    await player.restartRingbackForRouteChange();

    expect(player.isRingbackPlaying, isTrue);
    await player.stopRingback();
  });

  test('stopping clears the flag that makes starting idempotent', () async {
    await player.stopRingback();

    expect(player.isRingbackPlaying, isFalse);
  });

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

    tearDown(() async {
      await NotificationSoundPlayer.instance.stopIncomingRing();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('the incoming ring', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({
          ringtoneEnabledKey: false,
          callVibrationEnabledKey: true,
        });
      });

      test(
        'starts a repeating buzz tagged as a ringtone, not an alarm',
        () async {
          await player.startIncomingRing();

          final vibrate = calls.singleWhere((c) => c.method == 'vibrate');
          expect(vibrate.arguments['pattern'], callVibrationPattern);
          expect(vibrate.arguments['repeat'], 0);
          expect(vibrate.arguments['usage'], 'ringtone');
        },
      );

      test('a stop from an isolate that never started the ring still '
          'cancels the vibration', () async {
        expect(player.ownsIncomingRing, isFalse);

        await player.stopIncomingRing();

        expect(calls.map((c) => c.method), contains('cancel'));
      });

      test(
        'starting the ring claims the stop port, stopping releases it',
        () async {
          await player.startIncomingRing();

          expect(player.ownsIncomingRing, isTrue);
          expect(
            IsolateNameServer.lookupPortByName(ringStopPortName),
            isNotNull,
          );

          await player.stopIncomingRing();

          expect(player.ownsIncomingRing, isFalse);
          expect(IsolateNameServer.lookupPortByName(ringStopPortName), isNull);
        },
      );

      test('a stop sent to the port stops the ring in the isolate that owns '
          'it', () async {
        await player.startIncomingRing();
        calls.clear();

        IsolateNameServer.lookupPortByName(ringStopPortName)!.send(null);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(player.ownsIncomingRing, isFalse);
        expect(calls.map((c) => c.method), contains('cancel'));
      });

      test('a failing vibration platform never takes the stop down', () async {
        vibrateError = PlatformException(code: 'no vibrator');

        await expectLater(player.stopIncomingRing(), completes);
      });

      test(
        'a failing vibration platform names what failed, in the log',
        () async {
          vibrateError = PlatformException(code: 'no vibrator');
          final logs = <String>[];
          final originalDebugPrint = debugPrint;
          debugPrint = (String? message, {int? wrapWidth}) {
            if (message != null) logs.add(message);
          };
          addTearDown(() => debugPrint = originalDebugPrint);

          await player.stopIncomingRing();

          expect(
            logs,
            contains(
              predicate<String>(
                (m) => m.startsWith('zuno/sound: vibration cancel failed:'),
              ),
            ),
          );
        },
      );

      test('no vibrator on the device skips the buzz, not logged as a '
          'failure', () async {
        hasVibrator = false;
        final logs = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);

        await player.startIncomingRing();

        expect(calls.map((c) => c.method), isNot(contains('vibrate')));
        expect(
          logs,
          contains('zuno/sound: ring vibration skipped, no vibrator'),
        );
      });
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
