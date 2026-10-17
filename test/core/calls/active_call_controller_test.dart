import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_controller.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_status.dart';
import 'package:zuno/core/calls/models/call_surface.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../helpers/call_channel_mocks.dart';
import '../../helpers/fake_call_engine.dart';
import '../../helpers/fake_call_session.dart';

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

  test('a call replaced by another leaves the new call its notice and its '
      'call audio, started on its own route', () async {
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
      {'route': 'earpiece'},
    ]);
    expect(mocks.callAudioRunning, isTrue);
    expect(container.read(activeCallControllerProvider)?.session, same(second));
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
