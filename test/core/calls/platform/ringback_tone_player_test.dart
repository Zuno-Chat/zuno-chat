import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/platform/ringback_tone_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the native ringback tone', () {
    late RecordedMethodCalls native;
    late NativeRingbackTonePlayer player;

    setUp(() {
      player = NativeRingbackTonePlayer();
      native = installFakeCallsChannel();
    });

    test('starts and stops on the native side, once each', () async {
      await player.start();
      await player.start();
      expect(player.isPlaying, isTrue);
      await player.stop();
      await player.stop();

      expect(native.methods, ['startRingbackTone', 'stopRingbackTone']);
      expect(player.isPlaying, isFalse);
    });

    test('a failing platform side still leaves the tone stoppable', () async {
      installFakeCallsChannel(
        reply: (_) => throw PlatformException(code: 'tone'),
      );

      await expectLater(player.start(), completes);
      expect(player.isPlaying, isTrue);
      await expectLater(player.stop(), completes);
      expect(player.isPlaying, isFalse);
    });

    test('the ringtone preference off asks for nothing', () async {
      SharedPreferences.setMockInitialValues({ringtoneEnabledKey: false});

      await player.start();
      await player.stop();

      expect(native.calls, isEmpty);
      expect(player.isPlaying, isFalse);
    });

    test('a stop while the preference loads keeps the tone off', () async {
      final starting = player.start();
      await player.stop();
      await starting;

      expect(native.methods, isNot(contains('startRingbackTone')));
      expect(player.isPlaying, isFalse);
    });
  });

  group('picking the player', () {
    test('android and ios play the one native tone every caller shares', () {
      expect(
        ringbackTonePlayerFor(androidCapabilities),
        same(NativeRingbackTonePlayer.instance),
      );
      expect(
        ringbackTonePlayerFor(iosCapabilities),
        same(NativeRingbackTonePlayer.instance),
      );
    });

    test('a platform without native call audio or CallKit gets none, and '
        'asks native for nothing', () async {
      final native = installFakeCallsChannel();
      final none = ringbackTonePlayerFor(
        capabilitiesLike(androidCapabilities, nativeCallAudio: false),
      );

      await none.start();
      await none.stop();

      expect(none, isA<NoopRingbackTonePlayer>());
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
        android.read(ringbackTonePlayerProvider),
        same(NativeRingbackTonePlayer.instance),
      );
      expect(
        none.read(ringbackTonePlayerProvider),
        isA<NoopRingbackTonePlayer>(),
      );
    });
  });
}
