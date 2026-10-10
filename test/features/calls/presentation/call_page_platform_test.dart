import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/system_call_sync.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';

import '../../../helpers/fake_call_engine.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import 'call_page_harness.dart';

class _SlowVideoEngine extends FakeCallEngine {
  _SlowVideoEngine() : super(kind: CallKind.voice);

  final switched = Completer<void>();

  @override
  Future<void> switchToVideo() async {
    await switched.future;
    await super.switchToVideo();
  }
}

class _SlowVideoSession extends FakeCallSession {
  _SlowVideoSession()
    : super(room: CallPageHarness.buildRoom(), kind: CallKind.voice);

  final _engine = _SlowVideoEngine();

  @override
  _SlowVideoEngine get engine => _engine;
}

class _SlowPermissionSession extends FakeCallSession {
  _SlowPermissionSession()
    : super(room: CallPageHarness.buildRoom(), kind: CallKind.video);

  final granted = Completer<void>();

  @override
  Future<void> ensurePermissions() => granted.future;
}

class _NativeAudio {
  _NativeAudio(this.harness, {required this.route, this.headsets = const []}) {
    harness.callsReply = (call) => call.method == 'audioRoute'
        ? {'route': route, 'headsets': headsets}
        : null;
  }

  final CallPageHarness harness;
  String route;
  List<String> headsets;

  Future<void> changes({
    required String route,
    List<String> headsets = const [],
  }) async {
    this.route = route;
    this.headsets = headsets;
    harness.nativeEvents.add({
      'method': 'audioRouteChanged',
      'arguments': {'route': route, 'headsets': headsets},
    });
    await CallNotificationService.instance.takeQueuedNativeCalls();
    await harness.settle();
  }
}

void main() {
  FakeCallSession callerSession() => FakeCallSession(
    room: CallPageHarness.buildRoom(),
    kind: CallKind.voice,
    role: CallSessionRole.caller,
  );

  FakeCallSession calleeSession(CallKind kind) =>
      FakeCallSession(room: CallPageHarness.buildRoom(), kind: kind);

  FakeCallSession callInAnotherRoom({CallKind kind = CallKind.voice}) =>
      FakeCallSession(
        room: buildTestRoom(
          buildTestClient(userId: '@me:example.org'),
          id: '!other:example.org',
        ),
        kind: kind,
      );

  Future<void> startTalking(
    CallPageHarness harness,
    FakeCallSession session,
  ) async {
    await harness.open(session);
    session.engine.participants = [localParticipant(), remoteParticipant()];
    session.moveTo(CallSessionPhase.active);
    await harness.settle();
  }

  Future<FakeCallSession> talking(
    CallPageHarness harness,
    CallKind kind,
  ) async {
    final session = calleeSession(kind);
    await startTalking(harness, session);
    return session;
  }

  testWidgets('android runs the call in its service and plays ringback to '
      'the caller', (tester) async {
    final harness = CallPageHarness(tester, capabilities: androidCapabilities);
    final session = callerSession();
    await harness.open(session);

    expect(harness.count('startCallForegroundService'), 1);
    expect(harness.ringbackPlaying, isTrue);
    expect(harness.callAudioRunning, isTrue);

    session.end();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(harness.count('stopCallForegroundService'), 1);
    expect(harness.ringbackPlaying, isFalse);
    expect(harness.count('stopCallAudio'), 1);
    expect(harness.callAudioRunning, isFalse);
  });

  testWidgets('android: a headset that connects just as call audio starts '
      'takes the sound', (tester) async {
    final harness = CallPageHarness(tester, capabilities: androidCapabilities);
    harness.callsReply = (call) {
      if (call.method != 'audioRoute') return null;
      harness.headsets = ['bluetooth'];
      return {'headsets': <String>[]};
    };
    final session = callerSession();
    await harness.open(session);

    expect(harness.argsOf('startCallAudio'), [
      {'route': 'earpiece'},
    ]);
    expect(harness.audioRoute, 'bluetooth');
    expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);

    session.end();
    await harness.settle();
  });

  testWidgets('android: turning the camera back on in a video call lets the '
      'call service use it again', (tester) async {
    final harness = CallPageHarness(tester, capabilities: androidCapabilities);
    final session = await talking(harness, CallKind.video);

    await tester.tap(find.byTooltip('Turn camera on'));
    await harness.settle();

    expect(session.engine.cameraEnabledRequests, [true]);
    expect(
      [
        for (final args in harness.argsOf('startCallForegroundService'))
          (args! as Map)['withCamera'],
      ],
      [true, true],
    );
    await harness.close();
  });

  testWidgets('a speaker choice made before the call knows its route is '
      'kept', (tester) async {
    final harness = CallPageHarness(tester, capabilities: androidCapabilities);
    final session = _SlowPermissionSession();
    session.engine.participants = [localParticipant(camera: true)];
    await harness.open(session);

    await tester.tap(find.byTooltip('Turn speaker off'));
    await harness.settle();
    session.granted.complete();
    await harness.settle();

    expect(harness.audioRoute, 'earpiece');
    expect(harness.speakerIcon, Icons.hearing_outlined);
    await harness.close();
  });

  testWidgets('ios plays the native ringback, leaves the starting route to '
      'the system, and runs no call service', (tester) async {
    final harness = CallPageHarness(tester, capabilities: iosCapabilities);
    final session = callerSession();
    await harness.open(session);

    expect(find.byType(CallPage), findsOneWidget);
    expect(harness.ringbackPlaying, isTrue);
    expect(harness.count('setAudioRoute'), 0);
    expect(harness.count('startCallAudio'), 0);

    session.engine.participants = [localParticipant(), remoteParticipant()];
    session.moveTo(CallSessionPhase.active);
    await harness.settle();
    expect(harness.count('setAudioRoute'), 0);

    await tester.tap(find.byTooltip('Turn speaker on'));
    await harness.settle();

    expect(harness.argsOf('setAudioRoute'), [
      {'route': 'speaker'},
    ]);

    session.end();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(harness.ringbackPlaying, isFalse);
    expect(harness.count('stopCallAudio'), 0);
    expect(harness.count('startCallForegroundService'), 0);
    expect(harness.count('stopCallForegroundService'), 0);
    await harness.close();
  });

  testWidgets('an android build without a call service or native call audio '
      'still runs and ends the call, and asks for neither', (tester) async {
    final harness = CallPageHarness(
      tester,
      capabilities: capabilitiesLike(
        androidCapabilities,
        callForegroundService: false,
        nativeCallAudio: false,
      ),
    );
    final session = callerSession();
    await harness.open(session);

    expect(find.byType(CallPage), findsOneWidget);
    expect(harness.audioRoute, isNull);

    session.end();
    await harness.settle();

    expect(find.byType(CallPage), findsNothing);
    expect(harness.count('startCallForegroundService'), 0);
    expect(harness.count('stopCallForegroundService'), 0);
    expect(harness.count('startRingbackTone'), 0);
    expect(harness.count('stopRingbackTone'), 0);
    expect(harness.count('startCallAudio'), 0);
    expect(harness.count('stopCallAudio'), 0);
  });

  group('ios audio route', () {
    testWidgets('the call starts on the route the system reports, and nothing '
        'is sent to change it, even once the call goes active', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'speaker');
      final session = calleeSession(CallKind.voice);
      await harness.open(session);

      expect(harness.count('audioRoute'), 1);
      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(find.byTooltip('Turn speaker off'), findsOneWidget);
      expect(harness.proximityScreenOff, isFalse);

      session.engine.participants = [localParticipant(), remoteParticipant()];
      session.moveTo(CallSessionPhase.active);
      await harness.settle();

      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(harness.count('setAudioRoute'), 0);
      expect(harness.count('startCallAudio'), 0);
      await harness.close();
    });

    testWidgets('a video call leaves the speaker to the system: the reported '
        'route shows until the system moves it', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      final native = _NativeAudio(harness, route: 'earpiece');
      await talking(harness, CallKind.video);

      expect(harness.speakerIcon, Icons.hearing_outlined);
      expect(harness.count('setAudioRoute'), 0);

      await native.changes(route: 'speaker');

      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(harness.count('setAudioRoute'), 0);
      expect(harness.count('startCallAudio'), 0);
      await harness.close();
    });

    testWidgets('a route change the system reports with the same headsets is '
        'shown, and not sent back', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      final native = _NativeAudio(harness, route: 'earpiece');
      await talking(harness, CallKind.voice);
      expect(harness.speakerIcon, Icons.hearing_outlined);
      expect(harness.proximityScreenOff, isTrue);

      await native.changes(route: 'speaker');

      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(harness.proximityScreenOff, isFalse);
      expect(harness.count('setAudioRoute'), 0);

      await native.changes(route: 'earpiece');

      expect(harness.speakerIcon, Icons.hearing_outlined);
      expect(harness.count('setAudioRoute'), 0);
      await harness.close();
    });

    testWidgets('a headset connecting takes the sound, applied through the '
        'system', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      final native = _NativeAudio(harness, route: 'earpiece');
      await talking(harness, CallKind.voice);

      await native.changes(route: 'earpiece', headsets: ['bluetooth']);

      expect(harness.argsOf('setAudioRoute'), [
        {'route': 'bluetooth'},
      ]);
      expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);
      expect(harness.count('startCallAudio'), 0);
      await harness.close();
    });

    for (final (kind, fallback) in [
      (CallKind.voice, 'earpiece'),
      (CallKind.video, 'speaker'),
    ]) {
      testWidgets('losing the headset on a ${kind.name} call goes back to the '
          '$fallback, applied through the system', (tester) async {
        final harness = CallPageHarness(tester, capabilities: iosCapabilities);
        final native = _NativeAudio(
          harness,
          route: 'bluetooth',
          headsets: ['bluetooth'],
        );
        await talking(harness, kind);
        expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);

        await native.changes(route: 'earpiece');

        expect(harness.argsOf('setAudioRoute'), [
          {'route': fallback},
        ]);
        expect(harness.proximityScreenOff, kind == CallKind.voice);
        expect(harness.count('startCallAudio'), 0);
        await harness.close();
      });
    }

    testWidgets('a route change reported after the call ended sends nothing', (
      tester,
    ) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      final native = _NativeAudio(harness, route: 'earpiece');
      final session = await talking(harness, CallKind.voice);
      session.end();
      await harness.settle();
      expect(find.byType(CallPage), findsNothing);
      final reads = harness.count('audioRoute');

      await native.changes(route: 'earpiece', headsets: ['bluetooth']);

      expect(harness.count('audioRoute'), reads);
      expect(harness.count('setAudioRoute'), 0);
    });
  });

  group('ios system call', () {
    testWidgets('switching a voice call to video moves the sound from the ear '
        'to the speaker, and leaves reporting the video to the system call '
        'binding', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final session = await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('Switch to video call'));
      await harness.settle();

      expect(session.engine.switchToVideoCalls, 1);
      expect(session.kind, CallKind.video);
      expect(harness.count('upgradeCallToVideo'), 0);
      expect(harness.argsOf('setAudioRoute'), [
        {'route': 'speaker'},
      ]);
      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(harness.proximityScreenOff, isFalse);
      await harness.close();
    });

    testWidgets('switching to video on a headset keeps the sound on it', (
      tester,
    ) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'bluetooth', headsets: ['bluetooth']);
      await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('Switch to video call'));
      await harness.settle();

      expect(harness.count('setAudioRoute'), 0);
      expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);
      await harness.close();
    });

    testWidgets('End call hangs up as the user\'s own choice', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final session = await talking(harness, CallKind.voice);

      await tester.tap(find.byTooltip('End call'));
      await harness.settle();

      expect(session.hangUpsByUser, [true]);
      expect(session.endedByUser, isTrue);
      await harness.close();
    });
  });

  group('android switching a voice call to video', () {
    testWidgets('switches the engine, tells no system call, republishes '
        'membership, keeps the screen on and moves the sound from the ear to '
        'the speaker', (tester) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      final session = await talking(harness, CallKind.voice);
      expect(harness.audioRoute, 'earpiece');
      expect(harness.proximityScreenOff, isTrue);
      final routeChanges = harness.audioRouteChanges;

      await tester.tap(find.byTooltip('Switch to video call'));
      await harness.settle();

      expect(session.engine.switchToVideoCalls, 1);
      expect(session.kind, CallKind.video);
      expect(harness.count('upgradeCallToVideo'), 0);
      expect(
        [
          for (final args in harness.argsOf('startCallForegroundService'))
            (args! as Map)['withCamera'],
        ],
        [false, true],
      );
      expect(harness.argsOf('setAudioRoute'), [
        {'route': 'speaker'},
      ]);
      expect(harness.audioRouteChanges, routeChanges + 1);
      expect(harness.audioRoute, 'speaker');
      expect(harness.speakerIcon, Icons.volume_up_outlined);
      expect(harness.proximityScreenOff, isFalse);
      expect(harness.wakelockToggles, [true]);
      expect(session.membershipRefreshes, 1);
      await harness.close();
    });

    testWidgets('on a headset keeps the sound on it', (tester) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      harness.headsets = ['bluetooth'];
      final session = await talking(harness, CallKind.voice);
      expect(harness.audioRoute, 'bluetooth');
      final routeChanges = harness.audioRouteChanges;

      await tester.tap(find.byTooltip('Switch to video call'));
      await harness.settle();

      expect(session.kind, CallKind.video);
      expect(harness.audioRouteChanges, routeChanges);
      expect(harness.audioRoute, 'bluetooth');
      expect(harness.speakerIcon, Icons.bluetooth_audio_outlined);
      await harness.close();
    });

    testWidgets('with the speaker already on sends no route again', (
      tester,
    ) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      final session = await talking(harness, CallKind.voice);
      await tester.tap(find.byTooltip('Turn speaker on'));
      await harness.settle();
      expect(harness.audioRoute, 'speaker');
      final routeChanges = harness.audioRouteChanges;

      await tester.tap(find.byTooltip('Switch to video call'));
      await harness.settle();

      expect(session.kind, CallKind.video);
      expect(harness.audioRouteChanges, routeChanges);
      expect(harness.audioRoute, 'speaker');
      expect(harness.speakerIcon, Icons.volume_up_outlined);
      await harness.close();
    });
  });

  group('once the call has ended', () {
    testWidgets('android starts no call service and keeps no wakelock for a '
        'call that ended while the permission prompt was up', (tester) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      final session = _SlowPermissionSession();
      await harness.open(session);
      session.end();
      await harness.settle();
      expect(find.byType(CallPage), findsNothing);

      session.granted.complete();
      await harness.settle();

      expect(harness.count('startCallForegroundService'), 0);
      expect(harness.count('startCallAudio'), 0);
      expect(harness.callAudioRunning, isFalse);
      expect(harness.wakelockToggles, [false]);
      expect(harness.showOverLockscreen, isFalse);
    });

    testWidgets('android starts no call audio for a call that ended while its '
        'audio route was still being read', (tester) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      final reading = Completer<void>();
      harness.callsReply = (call) async {
        if (call.method == 'audioRoute') await reading.future;
        return null;
      };
      final session = callerSession();
      await harness.open(session);

      session.end();
      await harness.settle();
      reading.complete();
      await harness.settle();

      expect(harness.count('startCallAudio'), 0);
      expect(harness.callAudioRunning, isFalse);
    });

    testWidgets('ios moves no sound and keeps no wakelock for a switch to '
        'video that lands while the ended call\'s screen closes', (
      tester,
    ) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final session = _SlowVideoSession();
      await startTalking(harness, session);
      await tester.tap(find.byTooltip('Switch to video call'));
      await tester.pump();
      final closing = harness.wakelockGate = Completer<void>();
      session.end();
      await tester.pump();

      session.engine.switched.complete();
      await tester.pump();
      closing.complete();
      await harness.settle();

      expect(find.byType(CallPage), findsNothing);
      expect(harness.count('setAudioRoute'), 0);
      expect(harness.wakelockToggles, [false]);
      expect(session.kind, CallKind.voice);
      await harness.close();
    });

    testWidgets('ios sends nothing for the speaker button pressed as the '
        'call ends', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final session = await talking(harness, CallKind.voice);
      final closing = harness.wakelockGate = Completer<void>();

      session.end();
      await tester.idle();
      await tester.tap(find.byTooltip('Turn speaker on'));
      await tester.pump();
      closing.complete();
      await harness.settle();

      expect(find.byType(CallPage), findsNothing);
      expect(harness.count('setAudioRoute'), 0);
      await harness.close();
    });
  });

  group('ios, a call accepted as another ends', () {
    testWidgets('End & Accept while the ended call\'s screen still closes '
        'keeps the new call and its screen', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      harness.container.read(systemCallSyncProvider);
      final ended = await talking(harness, CallKind.voice);
      final closing = harness.wakelockGate = Completer<void>();
      ended.end();
      await tester.pump();
      expect(harness.container.read(activeCallProvider), isNull);

      final accepted = callInAnotherRoom();
      harness.pushCall(accepted);
      await harness.settle();
      closing.complete();
      await harness.settle();

      expect(harness.container.read(activeCallProvider), same(accepted));
      expect(find.byType(CallPage), findsOneWidget);
      expect(
        tester.widget<CallPage>(find.byType(CallPage)).call.session,
        same(accepted),
      );
      await harness.close();
    });

    testWidgets('a call screen that first builds after its call ended and '
        'another was accepted leaves the new call alone', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      harness.container.read(systemCallSyncProvider);
      await harness.showChat();
      final ended = calleeSession(CallKind.voice);
      harness.pushCall(ended);
      ended.end();
      await tester.idle();
      expect(harness.container.read(activeCallProvider), isNull);

      final accepted = callInAnotherRoom();
      harness.pushCall(accepted);
      await harness.settle();

      expect(harness.container.read(activeCallProvider), same(accepted));
      expect(find.byType(CallPage), findsOneWidget);
      expect(
        tester.widget<CallPage>(find.byType(CallPage)).call.session,
        same(accepted),
      );
      await harness.close();
    });

    testWidgets('a call screen that first builds after its call ended leaves '
        'the new video call\'s wakelock on', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      harness.container.read(systemCallSyncProvider);
      await harness.showChat();
      final ended = calleeSession(CallKind.voice);
      harness.pushCall(ended);
      ended.end();
      await tester.idle();

      final accepted = callInAnotherRoom(kind: CallKind.video);
      harness.pushCall(accepted);
      await harness.settle();

      expect(harness.container.read(activeCallProvider), same(accepted));
      expect(harness.wakelockToggles, [false, true]);
      await harness.close();
    });
  });

  group('releasing video renderers', () {
    List<String> rendererCalls(CallPageHarness harness, Object? texture) => [
      for (final call in harness.webrtc)
        if (call.arguments case {'textureId': final Object? id}
            when id == texture)
          switch (call.method) {
            'videoRendererSetSrcObject' =>
              (call.arguments as Map)['streamId'] == '' ? 'detach' : 'attach',
            'videoRendererDispose' => 'dispose',
            final method => method,
          },
    ];

    Future<(FakeCallSession, Object?)> remoteOnCamera(
      CallPageHarness harness,
    ) async {
      final session = await talking(harness, CallKind.video);
      session.engine.setParticipants([
        localParticipant(),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();
      final shown = harness.webrtc.lastWhere(
        (c) =>
            c.method == 'videoRendererSetSrcObject' &&
            (c.arguments as Map)['streamId'] == '@ann:example.org-video',
      );
      harness.webrtc.clear();
      return (session, (shown.arguments as Map)['textureId']);
    }

    testWidgets('ios takes the video off the renderer of someone who left '
        'and releases the renderer only after a pause', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final (session, texture) = await remoteOnCamera(harness);

      session.engine.setParticipants([localParticipant()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rendererCalls(harness, texture), ['detach']);

      await harness.settle();
      await harness.settle();
      expect(rendererCalls(harness, texture), ['detach', 'dispose']);
      await harness.close();
    });

    testWidgets('ios still releases the renderer when taking the video off '
        'fails', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final (session, texture) = await remoteOnCamera(harness);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('FlutterWebRTC.Method'),
            (call) async {
              harness.webrtc.add(call);
              if (call.method == 'videoRendererSetSrcObject') {
                throw PlatformException(code: 'renderer gone');
              }
              return null;
            },
          );

      session.engine.setParticipants([localParticipant()]);
      await harness.settle();
      await harness.settle();

      expect(rendererCalls(harness, texture), ['detach', 'dispose']);
      await harness.close();
    });

    testWidgets('ios takes the video off every renderer before releasing it '
        'when the call ends', (tester) async {
      final harness = CallPageHarness(tester, capabilities: iosCapabilities);
      _NativeAudio(harness, route: 'earpiece');
      final (session, texture) = await remoteOnCamera(harness);
      session.engine.setParticipants([
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);
      await harness.settle();
      final local =
          harness.webrtc
                  .lastWhere((c) => c.method == 'videoRendererSetSrcObject')
                  .arguments
              as Map;
      harness.webrtc.clear();

      session.end();
      await harness.settle();
      await harness.settle();

      expect(rendererCalls(harness, texture), ['detach', 'dispose']);
      expect(rendererCalls(harness, local['textureId']), ['detach', 'dispose']);
      expect(local['textureId'], isNot(texture));
      await harness.close();
    });

    testWidgets('android releases the renderer of someone who left straight '
        'away, without taking the video off first', (tester) async {
      final harness = CallPageHarness(
        tester,
        capabilities: androidCapabilities,
      );
      final (session, texture) = await remoteOnCamera(harness);

      session.engine.setParticipants([localParticipant()]);
      await harness.settle();

      expect(rendererCalls(harness, texture), ['dispose']);
      await harness.close();
    });
  });
}
