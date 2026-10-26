import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_controller.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/call_waiting_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_failure.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_status.dart';
import 'package:zuno/core/calls/models/call_surface.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/platform/call_tone_player.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/l10n/l10n.dart';

import '../../helpers/call_channel_mocks.dart';
import '../../helpers/fake_call_engine.dart';
import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  FakeCallSession voiceCall() =>
      FakeCallSession(room: buildCallRoom(), kind: CallKind.voice);

  ProviderContainer containerWithControllers() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeCallControllerProvider);
    return container;
  }

  test('a call takes the ongoing-call notice as soon as it is set, with no '
      'frame drawn', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();

    final call = voiceCall();
    container.read(activeCallProvider.notifier).set(call);
    await pumpEventQueue();

    expect(mocks.count('startCallForegroundService'), 1);
    expect(container.read(activeCallControllerProvider)?.session, same(call));
  });

  test('a call cleared before it ends gives back the notice it took', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();
    container.read(activeCallProvider.notifier).set(voiceCall());
    await pumpEventQueue();

    container.read(activeCallProvider.notifier).set(null);
    await pumpEventQueue();

    expect(mocks.count('stopCallForegroundService'), 1);
    expect(container.read(activeCallControllerProvider), isNull);
  });

  test('a call handed over to the next leaves it the notice and the call '
      'audio, on the route the first call was using', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();
    final first = FakeCallSession(room: buildCallRoom(), kind: CallKind.video);
    container.read(activeCallProvider.notifier).set(first);
    await pumpEventQueue();

    final second = voiceCall();
    container.read(activeCallProvider.notifier).set(second);
    await pumpEventQueue();

    expect(mocks.count('stopCallForegroundService'), 0);
    expect(mocks.count('stopCallAudio'), 0);
    expect(mocks.argsOf('startCallAudio'), [
      {'route': 'speaker'},
      {'route': 'speaker'},
    ]);
    expect(mocks.callAudioRunning, isTrue);
    expect(container.read(activeCallControllerProvider)?.session, same(second));
  });

  test('the call after one that ended starts on its own route', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();
    final first = FakeCallSession(room: buildCallRoom(), kind: CallKind.video);
    container.read(activeCallProvider.notifier).set(first);
    await pumpEventQueue();
    first.end();
    await pumpEventQueue();

    container.read(activeCallProvider.notifier).start(voiceCall);
    await pumpEventQueue();

    expect(mocks.argsOf('startCallAudio'), [
      {'route': 'speaker'},
      {'route': 'earpiece'},
    ]);
  });

  group('moderation', () {
    Future<(FakeCallSession, ActiveCallController)> onACall() async {
      CallChannelMocks();
      final container = containerWithControllers();
      final call = voiceCall();
      container.read(activeCallProvider.notifier).set(call);
      await pumpEventQueue();
      return (call, container.read(activeCallControllerProvider)!);
    }

    test('names whoever the call says muted us', () async {
      final (call, controller) = await onACall();
      expect(controller.mutedBy, isNull);

      call.mutedBy = '@ann:example.org';

      expect(controller.mutedBy?.calcDisplayname(), 'Ann');
    });

    test('the mute button asks the call to flip the microphone', () async {
      final (call, controller) = await onACall();
      call.engine.setParticipants([localParticipant(muted: true)]);
      await pumpEventQueue();

      await controller.toggleMute();

      expect(call.engine.microphoneMutedRequests, [false]);
    });

    test(
      'is offered on others only to someone in charge of the room',
      () async {
        final (call, controller) = await onACall();
        final ann = remoteParticipant();

        expect(controller.moderationGate()(ann), isFalse);

        setPowerLevels(call.room, {
          'users': {'@me:example.org': 50},
        });

        expect(controller.moderationGate()(ann), isTrue);
        expect(controller.moderationGate()(localParticipant()), isFalse);
      },
    );

    test('mute and remove ask the call for that person', () async {
      final (call, controller) = await onACall();

      await controller.mute(remoteParticipant());
      await controller.remove(remoteParticipant());

      expect(call.mutedPeople, ['@ann:example.org']);
      expect(call.removedPeople, ['@ann:example.org']);
    });
  });

  group('the message once the call ends', () {
    String? messageFor(void Function(FakeCallSession call) end) {
      final call = voiceCall();
      end(call);
      return call.endMessage(englishLocalizations);
    }

    test('names whoever removed us', () {
      expect(
        messageFor(
          (call) => call
            ..endReason = CallEndReason.removed
            ..removedBy = '@ann:example.org',
        ),
        'Ann removed you from the call.',
      );
    });

    test('says we were removed when the server alone told us', () {
      expect(
        messageFor((call) => call.endReason = CallEndReason.removed),
        'You were removed from this call.',
      );
    });

    test('reads a failure as its own sentence', () {
      expect(
        messageFor(
          (call) => call
            ..endReason = CallEndReason.failed
            ..failure = const CallConnectionLost(),
        ),
        'Connection lost',
      );
    });

    test('says nothing about a plain hang-up', () {
      expect(
        messageFor((call) => call.endReason = CallEndReason.hungUp),
        isNull,
      );
    });
  });

  group('the waiting tone', () {
    Set<CallTone> tones() => NativeCallTonePlayer.callAudio.playing;

    Future<FakeCallSession> onACall() async {
      CallChannelMocks();
      final container = containerWithControllers();
      final call = voiceCall();
      container.read(activeCallProvider.notifier).set(call);
      await pumpEventQueue();
      return call;
    }

    test('plays while another call rings, and stops with that ring', () async {
      final call = await onACall();

      SystemRing.instance.set(roomId: call.room.id, callId: 'waiting');
      await pumpEventQueue();
      expect(tones(), {CallTone.waiting});

      SystemRing.instance.clear('waiting');
      await pumpEventQueue();
      expect(tones(), isEmpty);
    });

    test('stops once its call ends, while the ring goes on', () async {
      final call = await onACall();
      SystemRing.instance.set(roomId: call.room.id, callId: 'waiting');
      await pumpEventQueue();

      call.end();
      await pumpEventQueue();

      expect(tones(), isEmpty);
      expect(SystemRing.instance.ringing.value?.callId, 'waiting');
    });

    test('plays for a ring already waiting when its call takes the line, '
        'whichever listener hears first', () async {
      CallChannelMocks();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(callWaitingProvider);
      container.read(activeCallControllerProvider);
      final call = voiceCall();
      SystemRing.instance.set(roomId: call.room.id, callId: 'waiting');
      await pumpEventQueue();

      container.read(activeCallProvider.notifier).set(call);
      await pumpEventQueue();

      expect(tones(), {CallTone.waiting});
    });

    test('never plays for the call on the line', () async {
      final call = await onACall();

      SystemRing.instance.set(roomId: call.room.id, callId: call.callId);
      await pumpEventQueue();

      expect(tones(), isEmpty);
    });
  });

  test('a call that ends before it starts never undoes the next call\'s '
      'device state', () async {
    final mocks = CallChannelMocks();
    final container = containerWithControllers();

    container.read(activeCallProvider.notifier).set(voiceCall()..end());
    container.read(activeCallProvider.notifier).set(voiceCall());
    await pumpEventQueue();

    expect(mocks.count('startCallForegroundService'), 1);
    expect(mocks.count('stopCallForegroundService'), 0);
    expect(mocks.count('startCallAudio'), 1);
    expect(mocks.count('stopCallAudio'), 0);
    expect(mocks.callAudioRunning, isTrue);
  });

  group('the ongoing-call notice once the call ends', () {
    test('stays until the call\'s last messages are out, while call audio '
        'stops at once', () async {
      final mocks = CallChannelMocks();
      final container = containerWithControllers();
      final call = voiceCall();
      final sending = Completer<void>();
      call.hangUpFinished = sending.future;
      container.read(activeCallProvider.notifier).set(call);
      await pumpEventQueue();

      call.end();
      await pumpEventQueue();

      expect(mocks.count('stopCallAudio'), 1);
      expect(mocks.count('stopCallForegroundService'), 0);

      sending.complete();
      await pumpEventQueue();

      expect(mocks.count('stopCallForegroundService'), 1);
    });

    test('goes once the wait for those messages runs out', () {
      fakeAsync((async) {
        final mocks = CallChannelMocks();
        final container = containerWithControllers();
        final call = voiceCall()..hangUpFinished = Completer<void>().future;
        container.read(activeCallProvider.notifier).set(call);
        async.flushMicrotasks();

        call.end();
        async.elapse(endMessagesWait - const Duration(seconds: 1));
        expect(mocks.count('stopCallForegroundService'), 0);

        async.elapse(const Duration(seconds: 1));
        expect(mocks.count('stopCallForegroundService'), 1);
      });
    });

    test('is left to a call that started meanwhile', () async {
      final mocks = CallChannelMocks();
      final container = containerWithControllers();
      final first = voiceCall();
      final sending = Completer<void>();
      first.hangUpFinished = sending.future;
      container.read(activeCallProvider.notifier).set(first);
      await pumpEventQueue();
      first.end();
      await pumpEventQueue();

      container.read(activeCallProvider.notifier).set(voiceCall());
      await pumpEventQueue();
      sending.complete();
      await pumpEventQueue();

      expect(mocks.count('startCallForegroundService'), 2);
      expect(mocks.count('stopCallForegroundService'), 0);
    });
  });

  group('the call status', () {
    const unkeyedMe = CallEngineParticipant(
      id: VoipParticipantId(userId: 'local', deviceId: 'local'),
      isLocal: true,
    );

    Future<CallStatus> statusOf(
      FakeCallSession session, {
      CallSessionPhase phase = CallSessionPhase.active,
      List<CallEngineParticipant> participants = const [],
    }) async {
      CallChannelMocks();
      final container = containerWithControllers();
      container.read(activeCallProvider.notifier).set(session);
      await pumpEventQueue();
      session.moveTo(phase);
      session.engine.setParticipants(participants);
      await pumpEventQueue();
      return container.read(activeCallControllerProvider)!.status;
    }

    test('a caller nobody answered yet is calling', () async {
      final caller = FakeCallSession(
        room: buildCallRoom(),
        kind: CallKind.voice,
        role: CallSessionRole.caller,
      );

      expect(
        await statusOf(caller, participants: [localParticipant()]),
        CallStatus.calling,
      );
    });

    test('a call still connecting says so, whoever the engine already '
        'lists', () async {
      expect(
        await statusOf(
          voiceCall(),
          phase: CallSessionPhase.connecting,
          participants: [localParticipant(), remoteParticipant()],
        ),
        CallStatus.connecting,
      );
    });

    test('a live call with nobody else there is waiting', () async {
      expect(
        await statusOf(voiceCall(), participants: [localParticipant()]),
        CallStatus.waiting,
      );
    });

    test('talking once both sides hold the keys', () async {
      expect(
        await statusOf(
          voiceCall(),
          participants: [localParticipant(), remoteParticipant()],
        ),
        CallStatus.talking,
      );
    });

    test('encrypting while either side lacks the keys, or before this side '
        'is known at all', () async {
      expect(
        await statusOf(
          voiceCall(),
          participants: [
            localParticipant(),
            remoteParticipant(encrypted: false),
          ],
        ),
        CallStatus.encrypting,
      );
      expect(
        await statusOf(
          voiceCall(),
          participants: [unkeyedMe, remoteParticipant()],
        ),
        CallStatus.encrypting,
      );
      expect(
        await statusOf(voiceCall(), participants: [remoteParticipant()]),
        CallStatus.encrypting,
      );
    });
  });

  test('a call that has already ended never builds its engine', () async {
    CallChannelMocks();
    final container = containerWithControllers();
    final ended = _EngineCountingSession()..end();

    container.read(activeCallProvider.notifier).set(ended);
    await pumpEventQueue();

    expect(ended.engineReads, 0);
  });

  test('a call shows on one surface at a time: its screen, then '
      'picture-in-picture, a window while the other camera is on, otherwise '
      'the bar', () async {
    CallChannelMocks();
    final pictureInPicture =
        CallNotificationService.instance.inPictureInPicture;
    addTearDown(() => pictureInPicture.value = false);
    final container = containerWithControllers();
    final session = voiceCall();
    container.read(activeCallProvider.notifier).set(session);
    await pumpEventQueue();
    final call = container.read(activeCallControllerProvider)!;
    var notified = 0;
    call.addListener(() => notified++);

    expect(call.surface, CallSurface.bar);

    session.moveTo(CallSessionPhase.active);
    session.engine.setParticipants([
      localParticipant(),
      remoteParticipant(camera: true),
    ]);
    await pumpEventQueue();
    expect(call.surface, CallSurface.window);

    call.screenOpen = true;
    expect(call.surface, CallSurface.screen);

    notified = 0;
    pictureInPicture.value = true;
    expect(call.surface, CallSurface.pictureInPicture);
    expect(notified, greaterThan(0));

    pictureInPicture.value = false;
    session.end();
    await pumpEventQueue();
    expect(call.surface, CallSurface.none);
  });
}

class _EngineCountingSession extends FakeCallSession {
  _EngineCountingSession() : super(room: buildCallRoom(), kind: CallKind.voice);

  int engineReads = 0;

  @override
  FakeCallEngine get engine {
    engineReads++;
    return super.engine;
  }
}
