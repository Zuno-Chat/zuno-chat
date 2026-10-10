import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/calls/system_call_sync.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_calls_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

const _roomId = '!room:example.org';
const _otherRoomId = '!other:example.org';
const _callId = 'call-1';
const _call = {'roomId': _roomId, 'callId': _callId};

Room _roomNamed(String id, String name) {
  final room = buildTestRoom(
    buildTestClient(userId: '@me:example.org'),
    id: id,
  );
  room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomName,
      senderId: '@me:example.org',
      stateKey: '',
      content: {'name': name},
    ),
  );
  return room;
}

Event _summaryOf(Room room, {String callId = _callId}) => buildTestEvent(
  room,
  eventId: '\$summary-$callId-${room.id}',
  senderId: '@ann:example.org',
  content: CallSummary(
    callId: callId,
    kind: 'voice',
    status: CallSummaryStatus.missed,
    durationMs: 0,
  ).toMessageContent(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordedMethodCalls native;
  late Map<String, Object?> startReply;
  Completer<void>? startGate;

  setUp(() async {
    installFakeLocalNotifications();
    startReply = {'muted': false};
    startGate = null;
    native = installFakeCallsChannel(
      reply: (call) async {
        if (call.method != 'startSystemCall') return null;
        await startGate?.future;
        return startReply;
      },
    );
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    native.clear();
  });

  ProviderContainer syncing(
    PlatformCapabilities capabilities, {
    CallSession? onCall,
  }) {
    final container = ProviderContainer(
      overrides: [platformCapabilitiesProvider.overrideWithValue(capabilities)],
    );
    addTearDown(container.dispose);
    if (onCall != null) container.read(activeCallProvider.notifier).set(onCall);
    container.read(systemCallSyncProvider);
    return container;
  }

  FakeCallSession newSession({
    CallKind kind = CallKind.voice,
    CallSessionRole role = CallSessionRole.callee,
    Room? room,
  }) => FakeCallSession(room: room ?? buildCallRoom(), kind: kind, role: role);

  Future<FakeCallSession> start(
    ProviderContainer container, [
    FakeCallSession? session,
  ]) async {
    final started = session ?? newSession();
    container.read(activeCallProvider.notifier).set(started);
    await pumpEventQueue();
    return started;
  }

  Future<void> goLive(
    FakeCallSession session, [
    List<CallEngineParticipant>? participants,
  ]) async {
    session.engine.participants = participants ?? [localParticipant()];
    session.moveTo(CallSessionPhase.active);
    await pumpEventQueue();
  }

  Future<void> show(
    FakeCallSession session,
    List<CallEngineParticipant> participants,
  ) async {
    session.engine.setParticipants(participants);
    await pumpEventQueue();
  }

  group('starting', () {
    for (final (kind, isVideo) in [
      (CallKind.voice, false),
      (CallKind.video, true),
    ]) {
      test('a ${kind.name} call starts a system call named after the room, '
          'unmuted', () async {
        final container = syncing(iosCapabilities);

        final session = await start(container, newSession(kind: kind));

        expect(native.methods, ['startSystemCall']);
        expect(native.calls.single.arguments, {
          ..._call,
          'title': 'Weekend hike',
          'isVideo': isVideo,
        });
        expect(session.engine.microphoneMutedRequests, isEmpty);
      });
    }

    test('a call already under way when syncing begins is started and '
        'reported connected', () async {
      final session = newSession()..everHadRemote = true;
      session.moveTo(CallSessionPhase.active);

      syncing(iosCapabilities, onCall: session);
      await pumpEventQueue();

      expect(native.methods, ['startSystemCall', 'reportCallConnected']);
      expect(native.argsOf('reportCallConnected'), [_call]);
    });

    test('a system call that is already muted mutes the call before it goes '
        'live, and the mute is not echoed back', () async {
      startReply = {'muted': true};
      final container = syncing(iosCapabilities);

      final session = await start(container);

      expect(session.engine.microphoneMutedRequests, [true]);
      expect(session.membershipRefreshes, 1);

      await goLive(session, [localParticipant(muted: true)]);

      expect(native.argsOf('setCallMuted'), isEmpty);
    });

    test('starting a call takes down the system ring for that call', () async {
      SystemRing.instance.set(roomId: _roomId, callId: _callId);
      final container = syncing(iosCapabilities);

      await start(container);

      expect(SystemRing.instance.ringing.value, isNull);
    });
  });

  group('connecting', () {
    test('the first remote to join reports the call connected, once', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session);

      session.remoteJoins();
      await pumpEventQueue();
      session.remoteJoins();
      await pumpEventQueue();

      expect(native.argsOf('reportCallConnected'), [_call]);
    });

    test('a remote who joins while the system call is still starting is '
        'reported connected once', () async {
      final gate = startGate = Completer<void>();
      final container = syncing(iosCapabilities);
      final session = await start(container);

      session.remoteJoins();
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect(native.methods, ['startSystemCall', 'reportCallConnected']);
    });
  });

  group('mute', () {
    test('the app mute reaches the system call screen when the call goes '
        'live and whenever it changes', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);

      await goLive(session, [localParticipant(muted: true)]);
      await show(session, [localParticipant(muted: true), remoteParticipant()]);
      await show(session, [localParticipant(), remoteParticipant()]);

      expect(native.argsOf('setCallMuted'), [
        {..._call, 'muted': true},
        {..._call, 'muted': false},
      ]);
    });

    for (final live in [true, false]) {
      test('a mute from the system call screen reaches the engine at once '
          '${live ? 'on a live call' : 'before the call connects'}, leaves '
          'publishing to the call, and is not echoed back', () async {
        final container = syncing(iosCapabilities);
        final session = await start(container);
        if (live) await goLive(session);

        await sendFromNative('setMuted', {..._call, 'muted': true});
        await pumpEventQueue();
        await show(session, [localParticipant(muted: true)]);

        expect(session.engine.microphoneMutedRequests, [true]);
        expect(session.membershipRefreshes, 1);
        expect(native.argsOf('setCallMuted'), isEmpty);
      });
    }

    test('an unmute from the system call screen after muting in the app is '
        'not echoed back', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session);
      await show(session, [localParticipant(muted: true)]);

      await sendFromNative('setMuted', {..._call, 'muted': false});
      await pumpEventQueue();
      await show(session, [localParticipant()]);

      expect(session.engine.microphoneMutedRequests, [false]);
      expect(native.argsOf('setCallMuted'), [
        {..._call, 'muted': true},
      ]);
    });

    test('the app mute before the call connects reaches the system call '
        'screen at once', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);

      await show(session, [localParticipant(muted: true)]);

      expect(session.phase, CallSessionPhase.connecting);
      expect(native.argsOf('setCallMuted'), [
        {..._call, 'muted': true},
      ]);
    });

    test('a system mute for another call is ignored', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session);

      await sendFromNative('setMuted', {
        'roomId': _roomId,
        'callId': 'call-2',
        'muted': true,
      });
      await pumpEventQueue();

      expect(session.engine.microphoneMutedRequests, isEmpty);
      expect(session.membershipRefreshes, 0);
    });
  });

  group('video', () {
    test('a voice call turns into a video call on the system screen once the '
        'local camera comes on, and a later remote camera does not report it '
        'again', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session, [localParticipant(), remoteParticipant()]);

      await show(session, [
        localParticipant(camera: true),
        remoteParticipant(),
      ]);

      expect(native.argsOf('upgradeCallToVideo'), [_call]);

      await show(session, [
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);
      await show(session, [localParticipant(), remoteParticipant()]);
      await show(session, [
        localParticipant(camera: true),
        remoteParticipant(),
      ]);

      expect(native.argsOf('upgradeCallToVideo'), [_call]);
    });

    test('a voice call turns into a video call on the system screen once a '
        'remote camera comes on, once', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session, [localParticipant(), remoteParticipant()]);

      await show(session, [
        localParticipant(),
        remoteParticipant(camera: true),
      ]);
      await show(session, [localParticipant(), remoteParticipant()]);
      await show(session, [
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);

      expect(native.argsOf('upgradeCallToVideo'), [_call]);
    });

    test('a video call is never upgraded', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container, newSession(kind: CallKind.video));

      await goLive(session, [
        localParticipant(camera: true),
        remoteParticipant(camera: true),
      ]);

      expect(native.argsOf('upgradeCallToVideo'), isEmpty);
    });
  });

  group('failure', () {
    test('a system call that did not connect hangs up with a message, and '
        'closes as failed', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);

      await sendFromNative('callFailed', _call);
      await pumpEventQueue();

      expect(session.failedMessage, callDidNotConnectMessage);
      expect(session.endReason, CallEndReason.failed);
      expect(session.hangUpsByUser, [false]);

      session.moveTo(CallSessionPhase.ended);
      await pumpEventQueue();

      expect(native.argsOf('endSystemCall'), [
        {..._call, 'reason': 'failed', 'byUser': false},
      ]);
    });

    test('a failure for another call changes nothing', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);

      await sendFromNative('callFailed', {
        'roomId': _roomId,
        'callId': 'call-2',
      });
      await pumpEventQueue();

      expect(session.hangUps, 0);
      expect(session.failedMessage, isNull);
      expect(session.endReason, isNull);
    });

    test('a failure after the call ended changes nothing', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      session.end();
      await pumpEventQueue();

      await sendFromNative('callFailed', _call);
      await pumpEventQueue();

      expect(session.hangUps, 0);
      expect(session.failedMessage, isNull);
      expect(session.endReason, CallEndReason.hungUp);
    });
  });

  group('ending', () {
    for (final (reason, closedAs) in [
      (CallEndReason.hungUp, 'remoteEnded'),
      (CallEndReason.declinedByThem, 'remoteEnded'),
      (CallEndReason.missed, 'unanswered'),
      (CallEndReason.failed, 'failed'),
    ]) {
      test('a call that ends as ${reason.name} closes its system call as '
          '$closedAs, once, and stops being the active call', () async {
        final container = syncing(iosCapabilities);
        final session = await start(container);

        session.end(reason: reason);
        await pumpEventQueue();

        expect(native.argsOf('endSystemCall'), [
          {..._call, 'reason': closedAs, 'byUser': false},
        ]);
        expect(container.read(activeCallProvider), isNull);
      });
    }

    test(
      'a call the user hung up closes its system call as ended by the user',
      () async {
        final container = syncing(iosCapabilities);
        final session = await start(container);
        await goLive(session);

        await session.hangUp(byUser: true);
        session.end();
        await pumpEventQueue();

        expect(native.argsOf('endSystemCall'), [
          {..._call, 'reason': 'remoteEnded', 'byUser': true},
        ]);
      },
    );

    test('nothing more reaches the system call screen once the call has '
        'ended', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session);
      session.end();
      await pumpEventQueue();
      native.clear();

      session.remoteJoins();
      await show(session, [
        localParticipant(muted: true),
        remoteParticipant(camera: true),
      ]);
      await sendFromNative('setMuted', {..._call, 'muted': true});
      await sendFromNative('callFailed', _call);
      await pumpEventQueue();

      expect(native.calls, isEmpty);
      expect(session.engine.microphoneMutedRequests, isEmpty);
      expect(session.hangUps, 0);
    });

    test('a call that ends while its system call is still starting ignores '
        'the late start reply', () async {
      final gate = startGate = Completer<void>();
      startReply = {'muted': true};
      final container = syncing(iosCapabilities);
      final session = await start(container);

      session.end();
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect(native.methods, ['startSystemCall', 'endSystemCall']);
      expect(session.engine.microphoneMutedRequests, isEmpty);
      expect(container.read(activeCallProvider), isNull);
    });
  });

  group('replacing', () {
    test('a call replaced before it ended closes its system call as failed, '
        'and the new call takes over', () async {
      final container = syncing(iosCapabilities);
      final first = await start(container);
      final second = await start(
        container,
        newSession(room: _roomNamed(_otherRoomId, 'Book club')),
      );

      expect(native.methods, [
        'startSystemCall',
        'endSystemCall',
        'startSystemCall',
      ]);
      expect(native.calls[1].arguments, {
        ..._call,
        'reason': 'failed',
        'byUser': false,
      });
      expect(native.calls[2].arguments, {
        'roomId': _otherRoomId,
        'callId': _callId,
        'title': 'Book club',
        'isVideo': false,
      });

      native.clear();
      first.remoteJoins();
      first.end();
      await pumpEventQueue();

      expect(native.calls, isEmpty);
      expect(container.read(activeCallProvider), same(second));

      second.remoteJoins();
      await pumpEventQueue();

      expect(native.argsOf('reportCallConnected'), [
        {'roomId': _otherRoomId, 'callId': _callId},
      ]);
    });

    for (final (order, pumpsBetween) in [('before', true), ('after', false)]) {
      test('a call that ends $order another call takes over leaves the new '
          'call active, its system call open', () async {
        final container = syncing(iosCapabilities);
        final first = await start(container);
        final second = newSession(room: _roomNamed(_otherRoomId, 'Book club'));

        first.end();
        if (pumpsBetween) await pumpEventQueue();
        container.read(activeCallProvider.notifier).set(second);
        await pumpEventQueue();

        expect(container.read(activeCallProvider), same(second));
        expect(
          [
            for (final args in native.argsOf('endSystemCall'))
              (args! as Map)['roomId'],
          ],
          [_roomId],
        );

        second.remoteJoins();
        await pumpEventQueue();

        expect(native.argsOf('reportCallConnected'), [
          {'roomId': _otherRoomId, 'callId': _callId},
        ]);
      });
    }

    test('a call cleared while its system call is still starting ignores the '
        'late start reply', () async {
      final gate = startGate = Completer<void>();
      startReply = {'muted': true};
      final container = syncing(iosCapabilities);
      final session = await start(container);

      container.read(activeCallProvider.notifier).set(null);
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect(native.methods, ['startSystemCall', 'endSystemCall']);
      expect(session.engine.microphoneMutedRequests, isEmpty);
    });
  });

  group('a callee nobody joined', () {
    test('hangs up once its call is summarised, without a summary of its '
        'own', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);

      session.room.client.onTimelineEvent.add(_summaryOf(session.room));
      await pumpEventQueue();

      expect(session.hangUpsByUser, [false]);
      expect(session.hangUpsSummarized, [true]);
    });

    test('only counts a summary of its own call in its own room', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      final timeline = session.room.client.onTimelineEvent;

      timeline.add(_summaryOf(session.room, callId: 'call-2'));
      timeline.add(
        _summaryOf(buildTestRoom(session.room.client, id: _otherRoomId)),
      );
      timeline.add(
        buildTestEvent(
          session.room,
          eventId: r'$text',
          senderId: '@ann:example.org',
          content: {
            'msgtype': MessageTypes.Text,
            'body': 'On my way',
            'call_id': _callId,
          },
        ),
      );
      await pumpEventQueue();

      expect(session.hangUps, 0);

      timeline.add(_summaryOf(session.room));
      await pumpEventQueue();

      expect(session.hangUps, 1);
    });

    test('is left alone by the summary once someone joined', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session);
      session.remoteJoins();
      await pumpEventQueue();

      session.room.client.onTimelineEvent.add(_summaryOf(session.room));
      await pumpEventQueue();

      expect(session.hangUps, 0);
    });

    test('rule does not apply to a caller', () async {
      final container = syncing(iosCapabilities);
      final session = await start(
        container,
        newSession(role: CallSessionRole.caller),
      );

      session.room.client.onTimelineEvent.add(_summaryOf(session.room));
      await pumpEventQueue();

      expect(session.hangUps, 0);
    });
  });

  group('the empty call timeout', () {
    FakeCallSession startIn(
      FakeAsync async, {
      CallSessionRole role = CallSessionRole.callee,
    }) {
      final container = syncing(iosCapabilities);
      final session = newSession(role: role);
      container.read(activeCallProvider.notifier).set(session);
      async.flushMicrotasks();
      return session;
    }

    test('hangs up a callee still alone that long after the call went live, '
        'not counting the time spent connecting', () {
      fakeAsync((async) {
        final session = startIn(async);
        async.elapse(emptyCallTimeout * 2);

        expect(session.hangUps, 0);

        session.moveTo(CallSessionPhase.active);
        async.elapse(emptyCallTimeout - const Duration(seconds: 1));

        expect(session.hangUps, 0);

        async.elapse(const Duration(seconds: 1));

        expect(session.hangUpsByUser, [false]);
        expect(session.hangUpsSummarized, [false]);
      });
    });

    test('keeps a callee someone joined before it ran out', () {
      fakeAsync((async) {
        final session = startIn(async);
        session.moveTo(CallSessionPhase.active);
        async.elapse(emptyCallTimeout - const Duration(seconds: 1));

        session.remoteJoins();
        async.elapse(emptyCallTimeout);

        expect(session.hangUps, 0);
        expect(native.argsOf('reportCallConnected'), [_call]);
      });
    });

    test('stops waiting once someone joins', () {
      fakeAsync((async) {
        final session = startIn(async);
        session.moveTo(CallSessionPhase.active);
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        session.remoteJoins();
        async.flushMicrotasks();

        expect(async.pendingTimers, isEmpty);
      });
    });

    test('stops with a call that ended first', () {
      fakeAsync((async) {
        final session = startIn(async);
        session.moveTo(CallSessionPhase.active);
        async.elapse(const Duration(seconds: 5));

        session.end();
        async.elapse(emptyCallTimeout);

        expect(session.hangUps, 0);
      });
    });

    test('never applies to a caller', () {
      fakeAsync((async) {
        final session = startIn(async, role: CallSessionRole.caller);
        session.moveTo(CallSessionPhase.active);
        async.elapse(emptyCallTimeout * 4);

        expect(session.hangUps, 0);
      });
    });

    test('stops with the sync going away mid-call', () {
      fakeAsync((async) {
        final container = syncing(iosCapabilities);
        final session = newSession();
        container.read(activeCallProvider.notifier).set(session);
        async.flushMicrotasks();
        session.moveTo(CallSessionPhase.active);
        async.flushMicrotasks();

        container.dispose();
        async.elapse(emptyCallTimeout * 2);

        expect(session.hangUps, 0);
      });
    });
  });

  group('the sync going away mid-call', () {
    test('closes no system call, and native reports after it reach '
        'nothing', () async {
      final container = syncing(iosCapabilities);
      final session = await start(container);
      await goLive(session);

      container.dispose();
      await sendFromNative('setMuted', {..._call, 'muted': true});
      await sendFromNative('callFailed', _call);
      session.end();
      await pumpEventQueue();

      expect(native.argsOf('endSystemCall'), isEmpty);
      expect(session.engine.microphoneMutedRequests, isEmpty);
      expect(session.membershipRefreshes, 0);
      expect(session.hangUps, 0);
      expect(session.failedMessage, isNull);
    });
  });

  group('without CallKit', () {
    test('on Android nothing reaches the system call screen and the call is '
        'left to the call screen', () async {
      final container = syncing(androidCapabilities);
      final session = await start(container);
      session.room.client.onTimelineEvent.add(_summaryOf(session.room));
      await goLive(session, [localParticipant(muted: true)]);
      await show(session, [
        localParticipant(),
        remoteParticipant(camera: true),
      ]);
      session.remoteJoins();
      await sendFromNative('setMuted', {..._call, 'muted': true});
      await sendFromNative('callFailed', _call);
      await pumpEventQueue();

      expect(session.engine.microphoneMutedRequests, isEmpty);
      expect(session.membershipRefreshes, 0);
      expect(session.hangUps, 0);
      expect(session.failedMessage, isNull);
      expect(session.endReason, isNull);

      session.end();
      await pumpEventQueue();

      expect(native.calls, isEmpty);
      expect(container.read(activeCallProvider), same(session));
    });

    test('a callee left alone on Android is not hung up by the timeout', () {
      fakeAsync((async) {
        final container = syncing(androidCapabilities);
        final session = newSession();
        container.read(activeCallProvider.notifier).set(session);
        session.moveTo(CallSessionPhase.active);
        async.elapse(emptyCallTimeout * 2);

        expect(session.hangUps, 0);
        expect(native.calls, isEmpty);
      });
    });

    test('the CallKit capability decides it, not the platform', () async {
      final container = syncing(
        capabilitiesLike(iosCapabilities, callKit: false),
      );

      await start(container);

      expect(native.calls, isEmpty);
    });
  });
}
