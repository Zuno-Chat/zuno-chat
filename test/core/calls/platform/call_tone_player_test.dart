import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/platform/call_tone_player.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the native call tones', () {
    late RecordedMethodCalls native;
    late NativeCallTonePlayer player;

    setUp(() {
      player = NativeCallTonePlayer.callAudio;
      native = installFakeCallsChannel();
    });

    test('ringback starts and stops on the native side, once each', () async {
      await player.start(CallTone.ringback);
      await player.start(CallTone.ringback);
      expect(player.playing, {CallTone.ringback});
      await player.stop(CallTone.ringback);
      await player.stop(CallTone.ringback);

      expect(native.methods, ['startRingbackTone', 'stopRingbackTone']);
      expect(player.playing, isEmpty);
    });

    test('starting a tone hands native the sound to loop', () async {
      await player.start(CallTone.ringback);
      await player.start(CallTone.waiting);

      expect(native.argsOf('startRingbackTone'), [
        {'asset': 'assets/sounds/ringback.wav'},
      ]);
      expect(native.argsOf('startWaitingTone'), [
        {'asset': 'assets/sounds/call_waiting.wav'},
      ]);
    });

    test(
      'the waiting tone starts and stops on its own, beside ringback',
      () async {
        await player.start(CallTone.ringback);
        await player.start(CallTone.waiting);
        await player.stop(CallTone.waiting);

        expect(native.methods, [
          'startRingbackTone',
          'startWaitingTone',
          'stopWaitingTone',
        ]);
        expect(player.playing, {CallTone.ringback});
      },
    );

    test('a failing platform side still leaves the tone stoppable', () async {
      installFakeCallsChannel(
        reply: (_) => throw PlatformException(code: 'tone'),
      );

      await expectLater(player.start(CallTone.waiting), completes);
      expect(player.playing, {CallTone.waiting});
      await expectLater(player.stop(CallTone.waiting), completes);
      expect(player.playing, isEmpty);
    });

    test('the ringtone preference off asks for neither tone', () async {
      SharedPreferences.setMockInitialValues({ringtoneEnabledKey: false});

      await player.start(CallTone.ringback);
      await player.start(CallTone.waiting);
      await player.stop(CallTone.ringback);
      await player.stop(CallTone.waiting);

      expect(native.calls, isEmpty);
      expect(player.playing, isEmpty);
    });

    test('a stop while the preference loads keeps the tone off', () async {
      final starting = player.start(CallTone.waiting);
      await player.stop(CallTone.waiting);
      await starting;

      expect(native.methods, isNot(contains('startWaitingTone')));
      expect(player.playing, isEmpty);
    });

    test('with CallKit the system plays the waiting tone, so native is never '
        'asked for it', () async {
      final callKit = NativeCallTonePlayer.callKit;

      await callKit.start(CallTone.waiting);
      await callKit.stop(CallTone.waiting);
      await callKit.start(CallTone.ringback);

      expect(native.methods, ['startRingbackTone']);
      expect(callKit.playing, {CallTone.ringback});
    });
  });

  group('the native join cue', () {
    late RecordedMethodCalls native;

    setUp(() => native = installFakeCallsChannel());

    test('is readied and played on the native side, on both '
        'platforms', () async {
      for (final player in [
        NativeCallTonePlayer.callAudio,
        NativeCallTonePlayer.callKit,
      ]) {
        await player.prepareJoinCue();
        await player.playJoinCue();
      }

      expect(native.argsOf('prepareCallCue'), [
        for (var i = 0; i < 2; i++) {'asset': 'assets/sounds/call_joined.wav'},
      ]);
      expect(native.argsOf('playCallCue'), [
        for (var i = 0; i < 2; i++) {'asset': 'assets/sounds/call_joined.wav'},
      ]);
    });

    test('plays with the ringtone preference off', () async {
      SharedPreferences.setMockInitialValues({ringtoneEnabledKey: false});

      await NativeCallTonePlayer.callAudio.playJoinCue();

      expect(native.methods, ['playCallCue']);
    });

    test('a failing platform side never fails the call', () async {
      installFakeCallsChannel(
        reply: (_) => throw PlatformException(code: 'cue'),
      );
      final player = NativeCallTonePlayer.callAudio;

      await expectLater(player.prepareJoinCue(), completes);
      await expectLater(player.playJoinCue(), completes);
    });
  });

  group('picking the player', () {
    test('android and ios each play the one native player every caller '
        'shares', () {
      expect(
        callTonePlayerFor(androidCapabilities),
        same(NativeCallTonePlayer.callAudio),
      );
      expect(
        callTonePlayerFor(iosCapabilities),
        same(NativeCallTonePlayer.callKit),
      );
    });

    test('a platform without native call audio or CallKit gets none, and '
        'asks native for nothing', () async {
      final native = installFakeCallsChannel();
      final none = callTonePlayerFor(
        capabilitiesLike(androidCapabilities, nativeCallAudio: false),
      );

      await none.start(CallTone.ringback);
      await none.start(CallTone.waiting);
      await none.stop(CallTone.ringback);
      await none.prepareJoinCue();
      await none.playJoinCue();

      expect(none, isA<NoopCallTonePlayer>());
      expect(native.calls, isEmpty);
    });

    test('the provider follows the platform capabilities', () {
      final android = ProviderContainer();
      addTearDown(android.dispose);
      final none = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            capabilitiesLike(androidCapabilities, nativeCallAudio: false),
          ),
        ],
      );
      addTearDown(none.dispose);

      expect(
        android.read(callTonePlayerProvider),
        same(NativeCallTonePlayer.callAudio),
      );
      expect(none.read(callTonePlayerProvider), isA<NoopCallTonePlayer>());
    });
  });

  group('the call tone sounds', () {
    Future<({int rate, List<int> samples})> sound(String asset) async {
      final bytes = (await rootBundle.load(asset)).buffer.asByteData();
      int? rate;
      for (var at = 12; at + 8 <= bytes.lengthInBytes;) {
        final id = String.fromCharCodes(bytes.buffer.asUint8List(at, 4));
        final size = bytes.getUint32(at + 4, Endian.little);
        final body = at + 8;
        if (id == 'fmt ') {
          expect(
            (
              bytes.getUint16(body, Endian.little),
              bytes.getUint16(body + 14, Endian.little),
            ),
            (1, 16),
            reason: '$asset is not 16-bit PCM, so its tone would hiss',
          );
          rate = bytes.getUint32(body + 4, Endian.little);
        } else if (id == 'data') {
          return (
            rate: rate!,
            samples: [
              for (var at = body; at + 2 <= body + size; at += 2)
                bytes.getInt16(at, Endian.little),
            ],
          );
        }
        at = body + size + size % 2;
      }
      throw StateError('$asset has no samples');
    }

    List<int> between(
      ({int rate, List<int> samples}) sound,
      double from,
      double to,
    ) => sound.samples.sublist(
      (from * sound.rate).round(),
      (to * sound.rate).round(),
    );

    bool silent(List<int> samples) => samples.every((sample) => sample == 0);

    double peak(List<int> samples) =>
        samples.map((sample) => sample.abs()).reduce(max) / 32767;

    test('ringback rings for a second, then rests for four', () async {
      final ringback = await sound(CallTone.ringback.asset);

      expect(ringback.samples, hasLength(5 * ringback.rate));
      expect(silent(between(ringback, 0, 1)), isFalse);
      expect(silent(between(ringback, 1, 5)), isTrue);
    });

    test(
      'the waiting tone is two short beeps, then a three-second rest',
      () async {
        final waiting = await sound(CallTone.waiting.asset);

        expect(waiting.samples, hasLength(4 * waiting.rate));
        expect(silent(between(waiting, 0, 0.2)), isFalse);
        expect(silent(between(waiting, 0.2, 0.8)), isTrue);
        expect(silent(between(waiting, 0.8, 1)), isFalse);
        expect(silent(between(waiting, 1, 4)), isTrue);
      },
    );

    double pitch(List<int> samples, int rate) {
      var signChanges = 0;
      for (var i = 1; i < samples.length; i++) {
        if ((samples[i - 1] < 0) != (samples[i] < 0)) signChanges++;
      }
      return signChanges / 2 / (samples.length / rate);
    }

    test('each beep is a 425 Hz tone at the set level', () async {
      final ringback = await sound(CallTone.ringback.asset);
      final beep = between(ringback, 0, 1);

      expect(pitch(beep, ringback.rate), closeTo(425, 2));
      expect(peak(beep), closeTo(0.3, 0.01));
    });

    test('each beep fades in and out, so it never clicks', () async {
      final waiting = await sound(CallTone.waiting.asset);

      for (final (from, to) in [(0.0, 0.2), (0.8, 1.0)]) {
        final beep = between(waiting, from, to);
        expect(peak(beep.sublist(0, 4)), lessThan(0.02));
        expect(peak(beep.sublist(beep.length - 4)), lessThan(0.02));
      }
    });

    double firstToSecondNote(({int rate, List<int> samples}) cue) =>
        pitch(between(cue, 0.32, 0.42), cue.rate) /
        pitch(between(cue, 0.01, 0.11), cue.rate);

    const joinCue = 'assets/sounds/call_joined.wav';

    test('the join cue rises a fourth', () async {
      expect(firstToSecondNote(await sound(joinCue)), closeTo(4 / 3, 0.04));
    });

    test('the join cue sounds at once and is over within half a second, at '
        'the beeps\' level', () async {
      final played = await sound(joinCue);

      expect(played.samples.length, lessThanOrEqualTo(played.rate ~/ 2));
      expect(silent(between(played, 0, 0.01)), isFalse);
      expect(peak(played.samples), closeTo(0.3, 0.05));
    });

    test('the join cue fades in and out, so it never clicks', () async {
      final samples = (await sound(joinCue)).samples;

      expect(peak(samples.sublist(0, 4)), lessThan(0.04));
      expect(peak(samples.sublist(samples.length - 4)), lessThan(0.02));
    });
  });
}
