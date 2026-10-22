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
}
