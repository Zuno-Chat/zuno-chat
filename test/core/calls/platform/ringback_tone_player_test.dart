import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/platform/ringback_tone_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final player = AndroidRingbackTonePlayer.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the ringtone preference off leaves no ringback to move', () async {
    SharedPreferences.setMockInitialValues({ringtoneEnabledKey: false});

    await player.start();

    expect(player.isPlaying, isFalse);
    await player.restartForRouteChange();
    expect(player.isPlaying, isFalse);
  });

  test('the ringback starts and stops with the preference on', () async {
    await player.start();
    expect(player.isPlaying, isTrue);

    await player.start();
    expect(player.isPlaying, isTrue);

    await player.stop();
    expect(player.isPlaying, isFalse);
  });

  test('a route change restarts a ringing tone', () async {
    await player.start();

    await player.restartForRouteChange();

    expect(player.isPlaying, isTrue);
    await player.stop();
  });

  test('stopping clears the flag that makes starting idempotent', () async {
    await player.stop();

    expect(player.isPlaying, isFalse);
  });

  group('the native ringback tone', () {
    late RecordedCallsChannel native;

    setUp(() => native = installFakeCallsChannel());

    test('starts and stops on the native side', () async {
      await player.start();
      await player.stop();

      expect(native.methods, ['startRingbackTone', 'stopRingbackTone']);
    });

    test('a route change stops and restarts it on the native side', () async {
      await player.start();
      await player.restartForRouteChange();
      await player.stop();

      expect(native.methods, [
        'startRingbackTone',
        'stopRingbackTone',
        'startRingbackTone',
        'stopRingbackTone',
      ]);
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

    test('is never asked for on a platform without one', () async {
      final none = ringbackTonePlayerFor(
        capabilitiesLike(androidCapabilities, nativeRingbackTone: false),
      );

      await none.start();
      await none.restartForRouteChange();
      await none.stop();

      expect(none, isA<NoopRingbackTonePlayer>());
      expect(native.calls, isEmpty);
      expect(player.isPlaying, isFalse);
    });
  });

  group('the CallKit ringback tone', () {
    late RecordedCallsChannel native;
    late CallKitRingbackTonePlayer callKit;

    setUp(() {
      callKit = CallKitRingbackTonePlayer();
      native = installFakeCallsChannel();
    });

    test('ios picks it', () {
      expect(
        ringbackTonePlayerFor(iosCapabilities),
        same(CallKitRingbackTonePlayer.instance),
      );
    });

    test('starts and stops on the native side, once each', () async {
      await callKit.start();
      await callKit.start();
      await callKit.stop();
      await callKit.stop();

      expect(native.methods, ['startRingbackTone', 'stopRingbackTone']);
    });

    test('a route change leaves the native tone alone', () async {
      await callKit.start();
      await callKit.restartForRouteChange();

      expect(native.methods, ['startRingbackTone']);
      expect(callKit.isPlaying, isTrue);
    });

    test('a failing platform side still leaves the tone stoppable', () async {
      installFakeCallsChannel(
        reply: (_) => throw PlatformException(code: 'tone'),
      );

      await expectLater(callKit.start(), completes);
      expect(callKit.isPlaying, isTrue);
      await expectLater(callKit.stop(), completes);
      expect(callKit.isPlaying, isFalse);
    });

    test('the ringtone preference off asks for nothing', () async {
      SharedPreferences.setMockInitialValues({ringtoneEnabledKey: false});

      await callKit.start();
      await callKit.stop();

      expect(native.calls, isEmpty);
      expect(callKit.isPlaying, isFalse);
    });

    test('a stop while the preference loads keeps the tone off', () async {
      final starting = callKit.start();
      await callKit.stop();
      await starting;

      expect(native.methods, isNot(contains('startRingbackTone')));
      expect(callKit.isPlaying, isFalse);
    });
  });

  group('picking the player', () {
    test('android plays the one native tone every caller shares', () {
      expect(ringbackTonePlayerFor(androidCapabilities), same(player));
    });

    test('the provider follows the platform capabilities', () {
      final android = ProviderContainer();
      addTearDown(android.dispose);
      final ios = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(iosCapabilities),
        ],
      );
      addTearDown(ios.dispose);

      expect(android.read(ringbackTonePlayerProvider), same(player));
      expect(
        ios.read(ringbackTonePlayerProvider),
        same(CallKitRingbackTonePlayer.instance),
      );
    });
  });
}
