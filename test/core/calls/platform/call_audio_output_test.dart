import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/call_audio_route.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/platform/call_audio_output.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const callsChannel = MethodChannel('zuno/calls');
  const webrtcChannel = MethodChannel('FlutterWebRTC.Method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordedCallsChannel native;
  late List<MethodCall> webrtc;
  late Future<Object?> Function() audioState;

  setUp(() {
    webrtc = [];
    audioState = () async => {
      'route': 'speaker',
      'headsets': ['wiredHeadset'],
    };
    native = installFakeCallsChannel(
      reply: (call) => switch (call.method) {
        'audioRoute' || 'startCallAudio' => audioState(),
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(webrtcChannel, (call) async {
      webrtc.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(webrtcChannel, null));
  });

  List<Object?> sentTo(List<MethodCall> calls) => [
    for (final call in calls) [call.method, call.arguments],
  ];

  void expectNothingConnected(CallAudioSnapshot snapshot, {String? reason}) {
    expect(snapshot.headsets, isEmpty, reason: reason);
    expect(snapshot.route, isNull, reason: reason);
  }

  group('reading the audio state native reports', () {
    test('reads the route in use and every headset connected', () {
      final snapshot = callAudioSnapshotFrom({
        'route': 'bluetooth',
        'headsets': ['wiredHeadset', 'bluetooth'],
      });

      expect(snapshot.route, CallAudioRoute.bluetooth);
      expect(snapshot.headsets, {
        CallAudioRoute.wiredHeadset,
        CallAudioRoute.bluetooth,
      });
    });

    test('skips names it does not know', () {
      final snapshot = callAudioSnapshotFrom({
        'route': 'carPlay',
        'headsets': ['carPlay', 'bluetooth', 7, null],
      });

      expect(snapshot.route, isNull);
      expect(snapshot.headsets, {CallAudioRoute.bluetooth});
    });

    test('no state, or one of the wrong shape, reads as no headsets and no '
        'route', () {
      for (final state in <Map<Object?, Object?>?>[
        null,
        {},
        {'route': 7, 'headsets': 'bluetooth'},
      ]) {
        expectNothingConnected(callAudioSnapshotFrom(state), reason: '$state');
      }
    });
  });

  group('picking the output', () {
    test('ios routes through native while CallKit runs the audio session', () {
      final output = callAudioOutputFor(iosCapabilities);

      expect(output, isA<NativeCallAudioOutput>());
      expect((output as NativeCallAudioOutput).startsSession, isFalse);
    });

    test('android routes through native and runs the audio session itself', () {
      final output = callAudioOutputFor(androidCapabilities);

      expect(output, isA<NativeCallAudioOutput>());
      expect((output as NativeCallAudioOutput).startsSession, isTrue);
    });

    test('every call gets an output of its own, so one call ending never '
        'stops the next call\'s watch', () {
      for (final capabilities in [androidCapabilities, iosCapabilities]) {
        expect(
          callAudioOutputFor(capabilities),
          isNot(same(callAudioOutputFor(capabilities))),
        );
      }
    });

    test('a platform without native call audio or CallKit reads nothing and '
        'asks native for nothing', () async {
      final output = callAudioOutputFor(
        capabilitiesLike(androidCapabilities, nativeCallAudio: false),
      );

      expectNothingConnected(await output.read());
      expect(await output.begin(CallAudioRoute.speaker), isNull);
      await output.apply(CallAudioRoute.earpiece);
      output.watch(() {});
      output.unwatch();
      await output.end();

      expect(output, isA<NoCallAudioOutput>());
      expect(native.calls, isEmpty);
    });
  });

  group('running the audio session', () {
    test('android starts call audio on the route it is given and stops '
        'it', () async {
      final output = NativeCallAudioOutput(startsSession: true);

      await output.begin(CallAudioRoute.bluetooth);
      await output.end();

      expect(sentTo(native.calls), [
        [
          'startCallAudio',
          {'route': 'bluetooth'},
        ],
        ['stopCallAudio', null],
      ]);
    });

    test(
      'android hears the headsets native sees as call audio starts',
      () async {
        final output = NativeCallAudioOutput(startsSession: true);

        final started = await output.begin(CallAudioRoute.speaker);

        expect(started?.headsets, {CallAudioRoute.wiredHeadset});
        expect(started?.route, CallAudioRoute.speaker);
      },
    );

    test('ios leaves the audio session to CallKit and hears nothing new as '
        'the call starts', () async {
      final output = NativeCallAudioOutput(startsSession: false);

      expect(await output.begin(CallAudioRoute.speaker), isNull);
      await output.end();

      expect(native.calls, isEmpty);
    });

    test('starting and stopping without a platform side is not an '
        'error', () async {
      messenger.setMockMethodCallHandler(callsChannel, null);
      final output = NativeCallAudioOutput(startsSession: true);

      expect(await output.begin(CallAudioRoute.speaker), isNull);
      await expectLater(output.end(), completes);
    });
  });

  for (final startsSession in [false, true]) {
    final platform = startsSession ? 'android' : 'ios';

    group('the native audio output on $platform', () {
      NativeCallAudioOutput output() =>
          NativeCallAudioOutput(startsSession: startsSession);

      Future<void> routeChanged({
        String route = 'bluetooth',
        List<String> headsets = const ['bluetooth'],
      }) async {
        await sendFromNative('audioRouteChanged', {
          'route': route,
          'headsets': headsets,
        });
        await pumpEventQueue();
      }

      setUp(() async {
        installFakeLocalNotifications();
        await CallNotificationService.instance.initialize(
          claimDeclinePort: false,
        );
      });

      test('reads the route and headsets from native', () async {
        final snapshot = await output().read();

        expect(snapshot.route, CallAudioRoute.speaker);
        expect(snapshot.headsets, {CallAudioRoute.wiredHeadset});
        expect(sentTo(native.calls), [
          ['audioRoute', null],
        ]);
      });

      test('a failing, missing or unreadable native side reads as no '
          'headsets and no route', () async {
        final reading = output();
        final answers = <String, Future<Object?> Function()>{
          'failing': () async => throw PlatformException(code: 'audio'),
          'not a map': () async => 'speaker',
          'empty': () async => null,
        };

        for (final MapEntry(key: reason, value: answer) in answers.entries) {
          audioState = answer;
          expectNothingConnected(await reading.read(), reason: reason);
        }
        messenger.setMockMethodCallHandler(callsChannel, null);
        expectNothingConnected(await reading.read(), reason: 'missing');
      });

      test('asks native for each route by name', () async {
        final routing = output();

        for (final route in CallAudioRoute.values) {
          await routing.apply(route);
        }

        expect(sentTo(native.calls), [
          for (final route in CallAudioRoute.values)
            [
              'setAudioRoute',
              {'route': route.name},
            ],
        ]);
      });

      test('routing without a platform side is not an error', () async {
        messenger.setMockMethodCallHandler(callsChannel, null);

        await expectLater(output().apply(CallAudioRoute.speaker), completes);
      });

      test('leaves flutter_webrtc audio routing alone', () async {
        final routing = output();

        await routing.read();
        await routing.begin(CallAudioRoute.speaker);
        await routing.apply(CallAudioRoute.speaker);
        routing.watch(() {});
        routing.unwatch();
        await routing.end();

        expect(webrtc, isEmpty);
      });

      test('a watch hears every route change native reports, until it '
          'stops', () async {
        final watching = output();
        var changes = 0;
        watching.watch(() => changes++);

        await routeChanged();
        await routeChanged();
        expect(changes, 2);

        watching.unwatch();
        await routeChanged();
        expect(changes, 2);
      });

      test('a watcher reading after a route change gets the state native '
          'pushed with it, without asking native again', () async {
        final watching = output();
        addTearDown(watching.unwatch);
        final reads = <CallAudioSnapshot>[];
        watching.watch(() => unawaited(watching.read().then(reads.add)));

        await routeChanged(route: 'wiredHeadset', headsets: ['wiredHeadset']);

        expect(reads.single.route, CallAudioRoute.wiredHeadset);
        expect(reads.single.headsets, {CallAudioRoute.wiredHeadset});
        expect(native.count('audioRoute'), 0);
      });

      test('a pushed state is read once, and the read after it asks '
          'native', () async {
        final watching = output();
        addTearDown(watching.unwatch);
        watching.watch(() {});
        await routeChanged();
        await watching.read();

        final next = await watching.read();

        expect(next.route, CallAudioRoute.speaker);
        expect(next.headsets, {CallAudioRoute.wiredHeadset});
        expect(native.count('audioRoute'), 1);
      });

      test('of several pushes before a read, the last one is read', () async {
        final watching = output();
        addTearDown(watching.unwatch);
        watching.watch(() {});

        await routeChanged(route: 'bluetooth');
        await routeChanged(route: 'speaker', headsets: []);
        final snapshot = await watching.read();

        expect(snapshot.route, CallAudioRoute.speaker);
        expect(snapshot.headsets, isEmpty);
        expect(native.count('audioRoute'), 0);
      });

      test('a state pushed before the watch stops is not read after '
          'it', () async {
        final watching = output();
        watching.watch(() {});
        await routeChanged();

        watching.unwatch();
        final snapshot = await watching.read();

        expect(snapshot.route, CallAudioRoute.speaker);
        expect(native.count('audioRoute'), 1);
      });

      test('a route change native cannot describe is not passed on', () async {
        final watching = output();
        addTearDown(watching.unwatch);
        var changes = 0;
        watching.watch(() => changes++);

        await sendFromNative('audioRouteChanged', 'bluetooth');
        await sendFromNative('audioRouteChanged');
        await pumpEventQueue();

        expect(changes, 0);
        expect((await watching.read()).route, CallAudioRoute.speaker);
        expect(native.count('audioRoute'), 1);
      });

      test('watching again replaces the earlier watch', () async {
        final watching = output();
        addTearDown(watching.unwatch);
        var first = 0;
        var second = 0;

        watching.watch(() => first++);
        watching.watch(() => second++);
        await routeChanged();

        expect(first, 0);
        expect(second, 1);
      });

      test('each output stops only its own watch', () async {
        final ending = output();
        final staying = output();
        addTearDown(staying.unwatch);
        var ended = 0;
        var stayed = 0;
        ending.watch(() => ended++);
        staying.watch(() => stayed++);

        ending.unwatch();
        ending.unwatch();
        await routeChanged();

        expect(ended, 0);
        expect(stayed, 1);
      });
    });
  }
}
