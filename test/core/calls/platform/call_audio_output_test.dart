import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  const webrtcEvents = MethodChannel('FlutterWebRTC.Event');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordedCallsChannel native;
  late List<MethodCall> webrtc;
  late Future<Object?> Function() audioState;
  late Future<Object?> Function() sources;

  Map<String, Object?> device(String id, {String kind = 'audiooutput'}) => {
    'deviceId': id,
    'groupId': id,
    'kind': kind,
    'label': id,
  };

  setUp(() {
    webrtc = [];
    audioState = () async => {
      'route': 'speaker',
      'headsets': ['wiredHeadset'],
    };
    sources = () async => {
      'sources': [device('earpiece'), device('speaker')],
    };
    native = installFakeCallsChannel(
      reply: (call) => call.method == 'audioRoute' ? audioState() : null,
    );
    messenger.setMockMethodCallHandler(webrtcChannel, (call) async {
      webrtc.add(call);
      return call.method == 'getSources' ? sources() : null;
    });
    messenger.setMockMethodCallHandler(webrtcEvents, (_) async => null);
    addTearDown(() {
      for (final channel in [webrtcChannel, webrtcEvents]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
  });

  List<Object?> sentTo(List<MethodCall> calls) => [
    for (final call in calls)
      if (call.method != 'initialize') [call.method, call.arguments],
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

  group('the CallKit audio output', () {
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
      final snapshot = await CallKitCallAudioOutput().read();

      expect(snapshot.route, CallAudioRoute.speaker);
      expect(snapshot.headsets, {CallAudioRoute.wiredHeadset});
      expect(sentTo(native.calls), [
        ['audioRoute', null],
      ]);
    });

    test('a failing, missing or unreadable native side reads as no headsets '
        'and no route', () async {
      final output = CallKitCallAudioOutput();
      final answers = <String, Future<Object?> Function()>{
        'failing': () async => throw PlatformException(code: 'audio'),
        'not a map': () async => 'speaker',
        'empty': () async => null,
      };

      for (final MapEntry(key: reason, value: answer) in answers.entries) {
        audioState = answer;
        expectNothingConnected(await output.read(), reason: reason);
      }
      messenger.setMockMethodCallHandler(callsChannel, null);
      expectNothingConnected(await output.read(), reason: 'missing');
    });

    test('asks native for each route by name', () async {
      final output = CallKitCallAudioOutput();

      for (final route in CallAudioRoute.values) {
        await output.apply(route);
      }

      expect(sentTo(native.calls), [
        [
          'setAudioRoute',
          {'route': 'earpiece'},
        ],
        [
          'setAudioRoute',
          {'route': 'speaker'},
        ],
        [
          'setAudioRoute',
          {'route': 'wiredHeadset'},
        ],
        [
          'setAudioRoute',
          {'route': 'bluetooth'},
        ],
      ]);
    });

    test('routing without a platform side is not an error', () async {
      messenger.setMockMethodCallHandler(callsChannel, null);

      await expectLater(
        CallKitCallAudioOutput().apply(CallAudioRoute.speaker),
        completes,
      );
    });

    test('leaves flutter_webrtc audio routing alone', () async {
      final output = CallKitCallAudioOutput();

      await output.read();
      await output.apply(CallAudioRoute.speaker);
      output.watch(() {});
      output.unwatch();

      expect(sentTo(webrtc), isEmpty);
    });

    test(
      'a watch hears every route change native reports, until it stops',
      () async {
        final output = CallKitCallAudioOutput();
        var changes = 0;
        output.watch(() => changes++);

        await routeChanged();
        await routeChanged();
        expect(changes, 2);

        output.unwatch();
        await routeChanged();
        expect(changes, 2);
      },
    );

    test('a watcher reading after a route change gets the state native pushed '
        'with it, without asking native again', () async {
      final output = CallKitCallAudioOutput();
      addTearDown(output.unwatch);
      final reads = <CallAudioSnapshot>[];
      output.watch(() => unawaited(output.read().then(reads.add)));

      await routeChanged(route: 'wiredHeadset', headsets: ['wiredHeadset']);

      expect(reads.single.route, CallAudioRoute.wiredHeadset);
      expect(reads.single.headsets, {CallAudioRoute.wiredHeadset});
      expect(native.count('audioRoute'), 0);
    });

    test('a pushed state is read once, and the read after it asks '
        'native', () async {
      final output = CallKitCallAudioOutput();
      addTearDown(output.unwatch);
      output.watch(() {});
      await routeChanged();
      await output.read();

      final next = await output.read();

      expect(next.route, CallAudioRoute.speaker);
      expect(next.headsets, {CallAudioRoute.wiredHeadset});
      expect(native.count('audioRoute'), 1);
    });

    test('of several pushes before a read, the last one is read', () async {
      final output = CallKitCallAudioOutput();
      addTearDown(output.unwatch);
      output.watch(() {});

      await routeChanged(route: 'bluetooth');
      await routeChanged(route: 'speaker', headsets: []);
      final snapshot = await output.read();

      expect(snapshot.route, CallAudioRoute.speaker);
      expect(snapshot.headsets, isEmpty);
      expect(native.count('audioRoute'), 0);
    });

    test('a state pushed before the watch stops is not read after '
        'it', () async {
      final output = CallKitCallAudioOutput();
      output.watch(() {});
      await routeChanged();

      output.unwatch();
      final snapshot = await output.read();

      expect(snapshot.route, CallAudioRoute.speaker);
      expect(native.count('audioRoute'), 1);
    });

    test('a route change native cannot describe is not passed on', () async {
      final output = CallKitCallAudioOutput();
      addTearDown(output.unwatch);
      var changes = 0;
      output.watch(() => changes++);

      await sendFromNative('audioRouteChanged', 'bluetooth');
      await sendFromNative('audioRouteChanged');
      await pumpEventQueue();

      expect(changes, 0);
      expect((await output.read()).route, CallAudioRoute.speaker);
      expect(native.count('audioRoute'), 1);
    });

    test('watching again replaces the earlier watch', () async {
      final output = CallKitCallAudioOutput();
      addTearDown(output.unwatch);
      var first = 0;
      var second = 0;

      output.watch(() => first++);
      output.watch(() => second++);
      await routeChanged();

      expect(first, 0);
      expect(second, 1);
    });

    test('each output stops only its own watch', () async {
      final ending = CallKitCallAudioOutput();
      final staying = CallKitCallAudioOutput();
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

  group('the flutter_webrtc audio output', () {
    setUp(() {
      addTearDown(() => navigator.mediaDevices.ondevicechange = null);
    });

    Future<void> deviceChangeFromWebRtc() async {
      await messenger.handlePlatformMessage(
        webrtcEvents.name,
        codec.encodeSuccessEnvelope({'event': 'onDeviceChange'}),
        null,
      );
      await pumpEventQueue();
    }

    test('makes the same flutter_webrtc calls for each route as the call '
        'page always did, and never asks CallKit', () async {
      final output = WebRtcCallAudioOutput();

      for (final route in CallAudioRoute.values) {
        await output.apply(route);
      }

      expect(sentTo(webrtc), [
        [
          'enableSpeakerphone',
          {'enable': false},
        ],
        [
          'enableSpeakerphone',
          {'enable': true},
        ],
        [
          'selectAudioOutput',
          {'deviceId': 'wired-headset'},
        ],
        [
          'selectAudioOutput',
          {'deviceId': 'bluetooth'},
        ],
      ]);
      expect(native.calls, isEmpty);
    });

    test('reads the headsets among the audio outputs and leaves the route to '
        'the call page', () async {
      sources = () async => {
        'sources': [
          device('earpiece'),
          device('speaker'),
          device('bluetooth'),
          device('wired-headset'),
        ],
      };

      final snapshot = await WebRtcCallAudioOutput().read();

      expect(snapshot.headsets, {
        CallAudioRoute.bluetooth,
        CallAudioRoute.wiredHeadset,
      });
      expect(snapshot.route, isNull);
      expect(sentTo(webrtc), [
        ['getSources', <String, Object?>{}],
      ]);
      expect(native.calls, isEmpty);
    });

    test('a headset heard only as an input is not an output', () async {
      sources = () async => {
        'sources': [
          device('earpiece'),
          device('speaker'),
          device('bluetooth', kind: 'audioinput'),
        ],
      };

      expectNothingConnected(await WebRtcCallAudioOutput().read());
    });

    test('a failing device list reads as no headsets', () async {
      sources = () async => throw PlatformException(code: 'getSources');

      expectNothingConnected(await WebRtcCallAudioOutput().read());
    });

    test('a watch hears the device changes flutter_webrtc reports, until it '
        'stops', () async {
      final output = WebRtcCallAudioOutput();
      var changes = 0;
      output.watch(() => changes++);

      await deviceChangeFromWebRtc();
      expect(changes, 1);

      output.unwatch();
      expect(navigator.mediaDevices.ondevicechange, isNull);
      await deviceChangeFromWebRtc();
      expect(changes, 1);
    });

    test('stopping leaves alone a device-change handler set after its '
        'own', () async {
      final ending = WebRtcCallAudioOutput();
      final staying = WebRtcCallAudioOutput();
      var ended = 0;
      var stayed = 0;
      ending.watch(() => ended++);
      staying.watch(() => stayed++);

      ending.unwatch();
      await deviceChangeFromWebRtc();

      expect(ended, 0);
      expect(stayed, 1);
    });

    test('an output that is not watching never clears the handler', () {
      void theirs(dynamic _) {}
      final output = WebRtcCallAudioOutput();
      navigator.mediaDevices.ondevicechange = theirs;

      output.unwatch();
      expect(navigator.mediaDevices.ondevicechange, same(theirs));

      output.watch(() {});
      output.unwatch();
      navigator.mediaDevices.ondevicechange = theirs;
      output.unwatch();
      expect(navigator.mediaDevices.ondevicechange, same(theirs));
    });
  });

  group('picking the audio output', () {
    test('android routes audio through flutter_webrtc, as before', () {
      expect(
        callAudioOutputFor(androidCapabilities),
        isA<WebRtcCallAudioOutput>(),
      );
    });

    test('ios routes audio through the CallKit audio session', () {
      expect(
        callAudioOutputFor(iosCapabilities),
        isA<CallKitCallAudioOutput>(),
      );
    });

    test('CallKit, not the platform name, decides', () {
      expect(
        callAudioOutputFor(
          capabilitiesLike(androidCapabilities, callKit: true),
        ),
        isA<CallKitCallAudioOutput>(),
      );
      expect(
        callAudioOutputFor(capabilitiesLike(iosCapabilities, callKit: false)),
        isA<WebRtcCallAudioOutput>(),
      );
    });

    test('every call gets an output of its own', () {
      for (final capabilities in [androidCapabilities, iosCapabilities]) {
        expect(
          identical(
            callAudioOutputFor(capabilities),
            callAudioOutputFor(capabilities),
          ),
          isFalse,
        );
      }
    });
  });
}
