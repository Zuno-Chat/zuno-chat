import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:permission_handler/permission_handler.dart';
import 'package:zuno/core/calls/call_connections.dart';
import 'package:zuno/core/calls/call_engine.dart';
import 'package:zuno/core/calls/livekit/livekit_signal_client.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_moderation.dart';
import 'package:zuno/core/calls/matrixrtc/call_sender_key_event.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_failure.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/calls/module/call_provider_discovery.dart';
import 'package:zuno/core/calls/module/calls_module.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/app_lifecycle.dart';
import '../../../helpers/call_fixtures.dart';
import '../../../helpers/call_membership.dart';
import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_call_connection.dart';
import '../../../helpers/fake_call_engine.dart';
import '../../../helpers/fake_call_provider_discovery.dart';
import '../../../helpers/fake_call_session.dart' show localParticipant;
import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_permissions.dart';
import '../../../helpers/hybrid_fake_async.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/send_recording_room.dart';
import '../../../helpers/to_device_recording_client.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _carol = '@carol:example.org';
const _caller = '@caller:example.org';
const _mallory = '@mallory:example.org';
const _encryptedFoci = {'encrypted': true};
const _callerDevice = VoipParticipantId(userId: _caller, deviceId: 'CALLERDEV');

int _publishedJoinTime(String body) =>
    parseRtcMemberships(jsonDecode(body) as Map<String, Object?>)
        .single
        .createdAtMs;

class _PublishCountingClient extends Client {
  _PublishCountingClient() : super('test', database: FakeDatabaseApi()) {
    setUserId(_me);
  }

  final publishes = <String>[];
  Object? refusal;

  @override
  String? get deviceID => 'TESTDEVICE';

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    if (eventType == callMemberEventType) publishes.add(jsonEncode(body));
    if (refusal case final error?) throw error;
    return '\$evt';
  }
}

typedef _KeyDeliveryCall = ({
  CallSession session,
  ToDeviceRecordingClient client,
  Room room,
});

typedef _CountingSession = ({
  CallSession session,
  _PublishCountingClient client,
  List<String> publishes,
  FakeCallEngine engine,
});

typedef _RoomCall = ({
  CallSession session,
  FakeCallEngine engine,
  SendRecordingRoom room,
});

Client buildCallTestClient(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = buildTestClient(
    userId: _me,
    deviceId: 'TESTDEVICE',
    httpClient: FakeHttpClient(handler),
  );
  client.baseUri = Uri.parse('https://example.org');
  client.bearerToken = 'test-token';
  return client;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late FakePermissions permissions;

  late Client client;
  late Room room;

  setUp(() {
    permissions = installFakePermissions();
    client = buildCallTestClient(
      (request) async => http.Response('{"event_id":"\$evt"}', 200),
    );
    room = buildTestRoom(client);
  });

  Uint8List testKey() => Uint8List.fromList(List<int>.generate(32, (i) => i));

  Iterable<String> reported(List<String> logs) =>
      logs.where((line) => line.startsWith('zuno/caught:'));

  MatrixException forbidden() => MatrixException.fromJson({
    'errcode': 'M_FORBIDDEN',
    'error': "You don't have permission to post that to the room.",
  });

  MatrixException badJson() =>
      MatrixException.fromJson({'errcode': 'M_BAD_JSON', 'error': 'bad event'});

  CallSession incoming({
    Room? inRoom,
    String callId = 'call1',
    CallKind kind = CallKind.voice,
    CallEngine? engine,
    Duration? keyDeliveryDelay,
    ValueListenable<bool>? pictureInPictureCamera,
    Future<void>? previousCallReleased,
  }) {
    final built = engine ?? FakeCallEngine();
    final session = CallSession.forIncoming(
      connections: FakeCallConnections(),
      room: inRoom ?? room,
      callId: callId,
      kind: kind,
      engineBuilder: () => built,
      keyDeliveryBaseDelay: keyDeliveryDelay,
      keyDeliveryMaxDelay: keyDeliveryDelay,
      pictureInPictureCamera: pictureInPictureCamera,
      previousCallReleased: previousCallReleased,
    );
    addTearDown(session.dispose);
    return session;
  }

  CallSession outgoing(
    Room r, {
    CallKind kind = CallKind.voice,
    CallEngine? engine,
    Duration? ringTimeout,
  }) {
    final built = engine ?? FakeCallEngine();
    final session = CallSession.startOutgoing(
      connections: FakeCallConnections(),
      r,
      kind,
      engineBuilder: () => built,
      ringTimeout: ringTimeout,
    );
    addTearDown(session.dispose);
    return session;
  }

  Future<void> untilPhase(CallSession session, CallSessionPhase phase) async {
    await session.phaseStream.firstWhere((p) => p == phase);
  }

  SendRecordingRoom sendRoom([Client? on]) =>
      SendRecordingRoom(client: on ?? client);

  void joinTheCall(
    Room r,
    String userId, {
    String deviceId = 'DEVICE',
    String callId = 'call1',
    Map<String, Object?> fociActive = const {},
    String? eventId,
    int createdAtMs = 0,
    Duration expiresIn = const Duration(minutes: 5),
  }) => r.setState(
    callMemberEvent(
      r,
      userId: userId,
      deviceId: deviceId,
      callId: callId,
      fociActive: fociActive,
      createdAtMs: createdAtMs,
      expiresIn: expiresIn,
      eventId: eventId,
    ),
  );

  void leaveTheCall(Room r, String userId) => r.setState(
    buildTestEvent(
      r,
      eventId: '\$left-$userId',
      senderId: userId,
      type: callMemberEventType,
      stateKey: userId,
      content: const {'memberships': <Object?>[]},
    ),
  );

  void joinMembers(Room r, List<String> userIds) {
    for (final id in userIds) {
      r.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          senderId: id,
          stateKey: id,
          content: {'membership': 'join'},
        ),
      );
    }
  }

  Event declineFrom(Room r, String senderId, String callId) => buildTestEvent(
    r,
    eventId: '\$decline_$senderId',
    senderId: senderId,
    content: {
      'msgtype': callDeclineMsgtype,
      'body': 'Call declined',
      'call_id': callId,
    },
  );

  Future<void> sync([Client? on]) async {
    (on ?? client).onSync.add(SyncUpdate(nextBatch: 'next'));
    await pumpEventQueue();
  }

  Client loggingMemberPuts(
    List<String> puts, {
    Future<http.Response?> Function(String body)? onPut,
  }) => buildCallTestClient((request) async {
    if (request.method == 'PUT' &&
        request.url.path.contains(callMemberEventType)) {
      puts.add(request.body);
      if (await onPut?.call(request.body) case final response?) {
        return response;
      }
    }
    return http.Response('{"event_id":"\$evt"}', 200);
  });

  Client recordingRequests(List<http.Request> requests) =>
      buildCallTestClient((request) async {
        requests.add(request);
        return http.Response('{"event_id":"\$evt"}', 200);
      });

  ToDeviceEvent keyEvent({
    String sender = _caller,
    String curveKey = 'curve-CALLERDEV',
    String callId = 'call1',
    SenderKey? key,
  }) => ToDeviceEvent(
    sender: sender,
    type: callSenderKeyEventType,
    content: buildSenderKeyContent(
      callId: callId,
      key: key ?? (epoch: 0, gen: 1, key: testKey()),
    ),
    encryptedContent: {'sender_key': curveKey, 'algorithm': 'm.olm.v1'},
  );

  ToDeviceEvent dummyFrom(
    String sender,
    String deviceId, {
    bool encrypted = true,
  }) => ToDeviceEvent(
    sender: sender,
    type: EventTypes.Dummy,
    content: const {},
    encryptedContent: encrypted
        ? {'sender_key': 'curve-$deviceId', 'algorithm': 'm.olm.v1'}
        : null,
  );

  _KeyDeliveryCall keyDeliveryCall({
    ToDeviceRecordingClient? over,
    Map<String, String> inCall = const {_bob: 'BOBDEVICE'},
    Map<String, Map<String, Object?>> fociActive = const {},
    CallEngine? engine,
    Duration? keyDeliveryDelay,
  }) {
    final c = over ?? ToDeviceRecordingClient();
    final r = buildTestRoom(c);
    for (final MapEntry(key: userId, value: deviceId) in inCall.entries) {
      setSelfSignedTestDevices(c, userId, [deviceId]);
      joinTheCall(
        r,
        userId,
        deviceId: deviceId,
        fociActive: fociActive[userId] ?? _encryptedFoci,
      );
    }
    return (
      session: incoming(
        inRoom: r,
        engine: engine,
        keyDeliveryDelay: keyDeliveryDelay,
      ),
      client: c,
      room: r,
    );
  }

  test(
    'a call whose engine accepts the key and joins reaches active',
    () async {
      final engine = FakeCallEngine();
      final session = incoming(engine: engine);
      final phases = <CallSessionPhase>[];
      session.phaseStream.listen(phases.add);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(session.endReason, isNull);
      expect(session.failure, isNull);
      expect(engine.joined, isTrue);
      expect(engine.ownKeys.keys, [0]);
      expect(engine.sendSlots, [0]);
      expect(phases, [CallSessionPhase.connecting, CallSessionPhase.active]);
    },
  );

  group('sad paths', () {
    test('a call whose encryption mechanism cannot encrypt the packets fails '
        'with an error', () async {
      final engine = FakeCallEngine(failKeys: true);
      final session = incoming(engine: engine);
      final phases = <CallSessionPhase>[];
      session.phaseStream.listen(phases.add);

      await expectLater(session.accept(), throwsA(isA<StateError>()));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(engine.joined, isFalse);
      expect(phases, [CallSessionPhase.connecting, CallSessionPhase.ended]);
    });

    test(
      'a key that arrives but cannot be applied ends the call as failed',
      () async {
        setSelfSignedTestDevices(client, _caller, ['CALLERDEV']);
        joinTheCall(room, _caller, deviceId: 'CALLERDEV');
        final session = incoming(engine: FakeCallEngine(failPeerKey: true));
        await session.accept();
        expect(session.phase, CallSessionPhase.active);

        client.onToDeviceEvent.add(keyEvent());
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failure, const CallDidNotConnect());
      },
    );

    test(
      'a hangup while the engine is still joining is not reported as a failure',
      () async {
        final gate = Completer<void>();
        final session = incoming(
          inRoom: sendRoom(),
          engine: FakeCallEngine(failJoin: true, joinGate: gate),
        );

        final accepting = session.accept();
        await pumpEventQueue();
        final hangingUp = session.hangUp();
        gate.complete();

        await expectLater(accepting, throwsA(isA<StateError>()));
        await hangingUp;

        expect(session.failure, isNull);
        expect(session.endReason, isNot(CallEndReason.failed));
      },
    );

    test('a callee whose engine fails to join ends as failed, tears the '
        'engine down and sends no decline, so its other phones can still '
        'answer', () async {
      final r = sendRoom();
      final engine = FakeCallEngine(failJoin: true);
      final session = incoming(inRoom: r, engine: engine);

      await expectLater(session.accept(), throwsStateError);
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallDidNotConnect());
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(r.attempts, isEmpty);
    });

    test('a room-permission failure surfaces a specific message', () async {
      final session = incoming(
        engine: FakeCallEngine(failJoin: true, joinError: forbidden()),
      );

      await expectLater(session.accept(), throwsA(isA<MatrixException>()));

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallNoPermissionToStart());
    });

    group('what an answer that fails reports', () {
      test(
        'a call that fails to connect is reported once, by the session',
        () async {
          final logs = recordDebugPrints();
          final session = incoming(engine: FakeCallEngine(failJoin: true));

          await expectLater(session.accept(), throwsStateError);

          expect(reported(logs), [startsWith('zuno/caught: accept a call:')]);
        },
      );

      test('a refusal the user is already shown is not reported', () async {
        final logs = recordDebugPrints();
        final session = incoming(
          engine: FakeCallEngine(failJoin: true, joinError: forbidden()),
        );

        await expectLater(session.accept(), throwsA(isA<MatrixException>()));

        expect(reported(logs), isEmpty);
      });

      test('a refusal of a defect in our own event is reported', () async {
        final logs = recordDebugPrints();
        final session = incoming(
          engine: FakeCallEngine(failJoin: true, joinError: badJson()),
        );

        await expectLater(session.accept(), throwsA(isA<MatrixException>()));

        expect(session.failure, const CallDidNotConnect());
        expect(reported(logs), [startsWith('zuno/caught: accept a call:')]);
      });

      test('a failure the calls module expects is not reported', () async {
        for (final error in <Object>[
          const CallsRouteGone('POST /sessions/new'),
          http.ClientException('offline'),
          const LiveKitSignalUnreachable('upgrade 503'),
        ]) {
          final logs = recordDebugPrints();
          final session = incoming(
            engine: FakeCallEngine(failJoin: true, joinError: error),
          );

          await expectLater(session.accept(), throwsA(same(error)));

          expect(reported(logs), isEmpty);
        }
      });

      test('a microphone refused at the prompt is not reported', () async {
        permissions.onRequest = permissionDenied;
        final logs = recordDebugPrints();
        final session = incoming();

        await expectLater(
          session.accept(),
          throwsA(isA<MicrophoneUnavailable>()),
        );

        expect(session.failure, const CallMicrophoneUnavailable());
        expect(reported(logs), isEmpty);
      });
    });

    test(
      'an engine that gives up reconnecting ends the call as failed',
      () async {
        final r = sendRoom();
        final engine = FakeCallEngine();
        final session = incoming(inRoom: r, engine: engine);
        await session.accept();
        expect(session.phase, CallSessionPhase.active);

        engine.statusController.add(CallEngineStatus.failed);
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failure, const CallConnectionLost());
        expect(r.sentEvents.last['call_id'], session.callId);
      },
    );

    test('a failed status that arrives while connecting is finishing does '
        'not get overwritten back to active', () async {
      final engine = FakeCallEngine();
      var injected = false;
      final raceClient = buildCallTestClient((request) async {
        if (!injected && request.method == 'PUT') {
          injected = true;
          engine.statusController.add(CallEngineStatus.failed);
          await pumpEventQueue();
        }
        return http.Response('{"event_id":"\$evt"}', 200);
      });
      final raceRoom = sendRoom(raceClient);
      final session = incoming(inRoom: raceRoom, engine: engine);

      await session.accept();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallConnectionLost());

      final callsBeforeSeed = engine.updatedRemotes.length;
      joinTheCall(raceRoom, _bob);
      await sync(raceClient);

      expect(engine.updatedRemotes.length, callsBeforeSeed);
    });
  });

  group('ensurePermissions', () {
    test(
      'memoized: two callers share exactly one underlying request',
      () async {
        final session = incoming();

        await Future.wait([
          session.ensurePermissions(),
          session.ensurePermissions(),
        ]);

        expect(permissions.requests, 1);
      },
    );

    test(
      'a rejected request stays rejected for every caller, not just the first',
      () async {
        permissions.onRequest = permissionDenied;
        final session = incoming();

        await expectLater(session.ensurePermissions(), throwsException);
        await expectLater(session.accept(), throwsException);
        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
      },
    );
  });

  group('asking for the microphone', () {
    setUp(() => permissions.onCheck = permissionDenied);

    tearDown(binding.resetInternalState);

    test('on iOS, without the microphone and with the app never coming to '
        'the front, the call fails after three seconds without a prompt', () {
      ambientCapabilities = iosCapabilities;
      moveLifecycleTo(binding, AppLifecycleState.paused);
      fakeAsync((async) {
        final engine = FakeCallEngine();
        final session = incoming(engine: engine);
        Object? failure;
        unawaited(
          session.accept().catchError((Object e) {
            failure = e;
          }),
        );

        async.elapse(const Duration(milliseconds: 2999));
        expect(session.phase, CallSessionPhase.connecting);
        expect(failure, isNull);

        async.elapse(const Duration(milliseconds: 1));

        expect(failure, isNotNull);
        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failure, const CallMicrophoneUnavailable());
        expect(permissions.calls, ['checkPermissionStatus']);
        expect(engine.joined, isFalse);
        expect(engine.startLocalMediaCalls, 0);
      });
    });

    test('on iOS, coming to the front after the wait has run out brings no '
        'prompt', () {
      ambientCapabilities = iosCapabilities;
      moveLifecycleTo(binding, AppLifecycleState.paused);
      fakeAsync((async) {
        final session = incoming();
        unawaited(session.accept().catchError((Object _) {}));
        async.elapse(const Duration(seconds: 3));

        moveLifecycleTo(binding, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(permissions.calls, ['checkPermissionStatus']);
        expect(session.phase, CallSessionPhase.ended);
      });
    });

    test('on iOS, coming to the front within the wait goes on to ask for the '
        'microphone', () {
      ambientCapabilities = iosCapabilities;
      moveLifecycleTo(binding, AppLifecycleState.paused);
      fakeAsync((async) {
        final session = incoming();
        var ready = false;
        unawaited(session.ensurePermissions().then((_) => ready = true));
        async.elapse(const Duration(seconds: 2));
        expect(permissions.calls, ['checkPermissionStatus']);
        expect(ready, isFalse);

        moveLifecycleTo(binding, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(permissions.calls, [
          'checkPermissionStatus',
          'requestPermissions',
        ]);
        expect(ready, isTrue);
      });
    });

    test('on iOS, with the microphone already allowed, nothing waits for the '
        'app to come to the front', () {
      ambientCapabilities = iosCapabilities;
      permissions.onCheck = permissionGranted;
      moveLifecycleTo(binding, AppLifecycleState.paused);
      fakeAsync((async) {
        final session = incoming();
        var ready = false;
        unawaited(session.ensurePermissions().then((_) => ready = true));
        async.flushMicrotasks();

        expect(permissions.calls, [
          'checkPermissionStatus',
          'requestPermissions',
        ]);
        expect(ready, isTrue);
      });
    });

    test('on iOS, with the app in the front, the microphone is asked for '
        'straight away', () {
      ambientCapabilities = iosCapabilities;
      moveLifecycleTo(binding, AppLifecycleState.resumed);
      fakeAsync((async) {
        final session = incoming();
        var ready = false;
        unawaited(session.ensurePermissions().then((_) => ready = true));
        async.flushMicrotasks();

        expect(permissions.calls, [
          'checkPermissionStatus',
          'requestPermissions',
        ]);
        expect(ready, isTrue);
      });
    });

    test('on iOS, a microphone turned off in Settings fails the call at once, '
        'without waiting for the app to come to the front or asking', () {
      ambientCapabilities = iosCapabilities;
      permissions.onCheck = permissionPermanentlyDenied;
      moveLifecycleTo(binding, AppLifecycleState.paused);
      fakeAsync((async) {
        final engine = FakeCallEngine();
        final session = incoming(engine: engine);

        expect(() => async.waitFor(session.accept()), throwsA(isException));
        expect(session.phase, CallSessionPhase.ended);
        expect(session.failure, const CallMicrophoneUnavailable());
        expect(permissions.calls, ['checkPermissionStatus']);
        expect(engine.joined, isFalse);
      });
    });

    test('on iOS, a microphone refused at the prompt fails the call with the '
        'microphone message', () async {
      ambientCapabilities = iosCapabilities;
      permissions.onRequest = permissionPermanentlyDenied;
      moveLifecycleTo(binding, AppLifecycleState.resumed);
      final session = incoming();

      await expectLater(session.accept(), throwsException);

      expect(permissions.calls, [
        'checkPermissionStatus',
        'requestPermissions',
      ]);
      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallMicrophoneUnavailable());
    });

    test('on Android, a microphone refused at the prompt fails the call with '
        'the microphone message too, never opening the microphone or '
        'joining', () async {
      ambientCapabilities = androidCapabilities;
      permissions.onRequest = permissionDenied;
      final engine = FakeCallEngine();
      final session = incoming(engine: engine);

      await expectLater(session.accept(), throwsException);

      expect(permissions.calls, ['requestPermissions']);
      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallMicrophoneUnavailable());
      expect(engine.startLocalMediaCalls, 0);
      expect(engine.joined, isFalse);
    });

    test('on Android, the microphone is asked for straight away even from '
        'the background', () {
      ambientCapabilities = androidCapabilities;
      moveLifecycleTo(binding, AppLifecycleState.paused);
      fakeAsync((async) {
        final session = incoming();
        var ready = false;
        unawaited(session.ensurePermissions().then((_) => ready = true));
        async.flushMicrotasks();

        expect(permissions.calls, ['requestPermissions']);
        expect(ready, isTrue);
      });
    });
  });

  group('the app going to the background', () {
    setUp(() => moveLifecycleTo(binding, AppLifecycleState.resumed));
    tearDown(() => moveLifecycleTo(binding, AppLifecycleState.resumed));

    CallSession answering(
      FakeCallEngine engine, {
      ValueListenable<bool>? pictureInPictureCamera,
    }) => incoming(
      kind: CallKind.video,
      engine: engine,
      pictureInPictureCamera: pictureInPictureCamera,
    );

    test('tells the engine where the app is at join, then each time it '
        'hides or comes back', () async {
      final engine = FakeCallEngine();

      await answering(engine).accept();
      await pumpEventQueue();
      moveLifecycleTo(binding, AppLifecycleState.paused);
      moveLifecycleTo(binding, AppLifecycleState.resumed);

      expect(engine.appInBackgroundRequests, [false, true, false]);
    });

    test(
      'a call answered in the background starts in the background',
      () async {
        moveLifecycleTo(binding, AppLifecycleState.paused);
        final engine = FakeCallEngine();

        await answering(engine).accept();
        await pumpEventQueue();

        expect(engine.appInBackgroundRequests, [true]);
      },
    );

    test(
      'a picture-in-picture window that can use the camera keeps it while '
      'the app is hidden, and losing it brings the placeholder back',
      () async {
        final pictureInPicture = ValueNotifier(false);
        final engine = FakeCallEngine();
        await answering(
          engine,
          pictureInPictureCamera: pictureInPicture,
        ).accept();
        await pumpEventQueue();

        pictureInPicture.value = true;
        moveLifecycleTo(binding, AppLifecycleState.paused);
        pictureInPicture.value = false;
        pictureInPicture.value = true;
        moveLifecycleTo(binding, AppLifecycleState.resumed);
        pictureInPicture.value = false;

        expect(engine.appInBackgroundRequests, [false, true, false]);
      },
    );

    test('a call answered in the background follows the window from the '
        'start', () async {
      moveLifecycleTo(binding, AppLifecycleState.paused);
      final pictureInPicture = ValueNotifier(false);
      final engine = FakeCallEngine();

      await answering(
        engine,
        pictureInPictureCamera: pictureInPicture,
      ).accept();
      await pumpEventQueue();
      pictureInPicture.value = true;
      pictureInPicture.value = false;

      expect(engine.appInBackgroundRequests, [true, false, true]);
    });

    test('a caller follows the app to the background from the moment its '
        'camera opens, before its invite is out', () async {
      final r = sendRoom()..sendGate = Completer<void>();
      final engine = FakeCallEngine(kind: CallKind.video);
      outgoing(r, kind: CallKind.video, engine: engine);
      await pumpEventQueue();

      moveLifecycleTo(binding, AppLifecycleState.paused);

      expect(r.sentEvents, isEmpty);
      expect(engine.appInBackgroundRequests, [false, true]);
      r.sendGate!.complete();
    });

    test('once the call ends, neither the app hiding nor the window reaches '
        'the engine', () async {
      final pictureInPicture = ValueNotifier(false);
      final engine = FakeCallEngine();
      final session = answering(
        engine,
        pictureInPictureCamera: pictureInPicture,
      );
      await session.accept();
      await pumpEventQueue();

      await session.hangUp(summarized: true);
      moveLifecycleTo(binding, AppLifecycleState.paused);
      pictureInPicture.value = true;

      expect(engine.appInBackgroundRequests, [false]);
    });
  });

  test('an outgoing call makes its own 32-byte key, and two calls never make '
      'the same one', () async {
    final engineA = FakeCallEngine();
    final sessionA = outgoing(sendRoom(), engine: engineA);
    await untilPhase(sessionA, CallSessionPhase.active);

    final engineB = FakeCallEngine();
    final sessionB = outgoing(sendRoom(), engine: engineB);
    await untilPhase(sessionB, CallSessionPhase.active);

    expect(engineA.ownKeys[0], hasLength(32));
    expect(engineB.ownKeys[0], hasLength(32));
    expect(engineA.ownKeys[0], isNot(engineB.ownKeys[0]));
  });

  group('delivering our key to the devices in the call', () {
    late List<String> keyQueries;
    late bool failNextQuery;
    late Client deliveryClient;
    late Room deliveryRoom;

    setUp(() {
      keyQueries = [];
      failNextQuery = false;
      deliveryClient = buildCallTestClient((request) async {
        if (request.url.path.endsWith('/keys/query')) {
          keyQueries.add(request.body);
          if (failNextQuery) {
            failNextQuery = false;
            return http.Response('boom', 500);
          }
          return http.Response(jsonEncode({'device_keys': {}}), 200);
        }
        return http.Response('{"event_id":"\$evt"}', 200);
      });
      deliveryRoom = buildTestRoom(deliveryClient);
    });

    CallSession delivering() =>
        incoming(inRoom: deliveryRoom, keyDeliveryDelay: Duration.zero);

    void bobInCall([Map<String, Object?> fociActive = _encryptedFoci]) =>
        joinTheCall(
          deliveryRoom,
          _bob,
          deviceId: 'BOBDEVICE',
          fociActive: fociActive,
        );

    test('a device is asked for its device keys the moment it is '
        'discovered', () async {
      bobInCall();
      final session = delivering();

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(keyQueries.first, contains(_bob));
    });

    test('a failed device-key fetch is retried', () async {
      failNextQuery = true;
      bobInCall();

      await delivering().accept();
      await pumpEventQueue();

      expect(keyQueries.length, greaterThanOrEqualTo(2));
    });

    test('a device whose keys are already known is sent the key without '
        'asking the server for them again', () async {
      setTestDevices(deliveryClient, _bob, {'BOBDEVICE': null});
      bobInCall();
      joinTheCall(
        deliveryRoom,
        _caller,
        deviceId: 'CALLERDEV',
        fociActive: _encryptedFoci,
      );

      await delivering().accept();
      await pumpEventQueue();

      expect(keyQueries.where((query) => query.contains(_caller)), isNotEmpty);
      expect(keyQueries.where((query) => query.contains(_bob)), isEmpty);
    });

    test('a device missing from an up-to-date device list counts as signed '
        'out: no query, no key and no retries', () async {
      final logs = recordDebugPrints();
      setTestDevices(deliveryClient, _bob, {'BOBOLDDEVICE': null});
      bobInCall();

      await delivering().accept();
      await pumpEventQueue();

      expect(logs.where((l) => l.startsWith('zuno/retry:')), isEmpty);
      expect(keyQueries, isEmpty);
    });

    test('a device missing from an up-to-date device list is asked for once '
        'the server says that user\'s devices changed', () async {
      setTestDevices(deliveryClient, _bob, {'BOBOLDDEVICE': null});
      bobInCall();
      await delivering().accept();
      await pumpEventQueue();
      expect(keyQueries, isEmpty);

      deliveryClient.userDeviceKeys[_bob]!.outdated = true;
      await sync(deliveryClient);

      expect(keyQueries.where((query) => query.contains(_bob)), isNotEmpty);
    });

    test('a device missing from a device list still out of date is asked for '
        'again', () async {
      setTestDevices(deliveryClient, _bob, {
        'BOBOLDDEVICE': null,
      }, outdated: true);
      bobInCall();

      await delivering().accept();
      await pumpEventQueue();

      expect(keyQueries.where((query) => query.contains(_bob)), isNotEmpty);
    });

    test('a known device whose only fociActive sessionId changes is not sent '
        'the key again', () async {
      final call = keyDeliveryCall();
      await call.session.accept();
      await pumpEventQueue();
      expect(call.client.tries, ['BOBDEVICE']);

      joinTheCall(
        call.room,
        _bob,
        deviceId: 'BOBDEVICE',
        fociActive: {..._encryptedFoci, 'sessionId': 'bob-session-2'},
      );
      await sync(call.client);

      expect(call.client.tries, ['BOBDEVICE']);
    });

    _KeyDeliveryCall deliveringOverToDevice(
      FakeAsync async, {
      ToDeviceRecordingClient? over,
    }) {
      final call = keyDeliveryCall(
        over: over ?? (ToDeviceRecordingClient()..unreachable.add('BOBDEVICE')),
      );
      unawaited(call.session.accept());
      async.flushMicrotasks();
      return call;
    }

    int triesFor(_KeyDeliveryCall call, String deviceId) =>
        call.client.tries.where((d) => d == deviceId).length;

    test('a delivery whose sends fail for seconds still delivers the key once '
        'the server answers, and then stops', () {
      fakeAsync((async) {
        final call = deliveringOverToDevice(async);
        async.elapse(const Duration(seconds: 8));
        expect(call.client.keysSent, isEmpty);

        call.client.unreachable.clear();
        async.elapse(const Duration(seconds: 5));

        final sent = call.client.keysSent['BOBDEVICE'];
        expect(sent, isNotNull);
        expect(
          parseSenderKeyContent(
            sent!.cast<String, Object?>(),
            callId: 'call1',
          )?.gen,
          1,
        );
        final tries = call.client.tries.length;
        async.elapse(const Duration(minutes: 1));
        expect(call.client.tries, hasLength(tries));
      });
    });

    for (final (ending, end) in [
      ('a hang-up', (CallSession s) => unawaited(s.hangUp())),
      ('letting the call go', (CallSession s) => s.dispose()),
    ]) {
      test('a delivery keeps trying while its device is in the call, and '
          '$ending stops it at once', () {
        fakeAsync((async) {
          final call = deliveringOverToDevice(async);
          async.elapse(const Duration(seconds: 30));
          expect(triesFor(call, 'BOBDEVICE'), greaterThan(3));

          end(call.session);
          async.flushMicrotasks();
          final tries = call.client.tries.length;
          async.elapse(const Duration(minutes: 1));

          expect(call.client.tries, hasLength(tries));
          expect(async.pendingTimers, isEmpty);
        });
      });
    }

    test('a delivery stops once its device leaves a call that goes on', () {
      fakeAsync((async) {
        final call = deliveringOverToDevice(async);
        setSelfSignedTestDevices(call.client, _caller, ['CALLERDEV']);
        joinTheCall(
          call.room,
          _caller,
          deviceId: 'CALLERDEV',
          fociActive: _encryptedFoci,
        );
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 30));
        expect(call.client.keysSent.keys, ['CALLERDEV']);
        expect(triesFor(call, 'BOBDEVICE'), greaterThan(3));

        leaveTheCall(call.room, _bob);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.flushMicrotasks();
        final tries = triesFor(call, 'BOBDEVICE');
        async.elapse(const Duration(minutes: 1));

        expect(triesFor(call, 'BOBDEVICE'), tries);
        expect(call.session.phase, CallSessionPhase.active);
      });
    });

    test(
      'a delivery that keeps failing is reported once, without the device it '
      'was for',
      () {
        final logs = recordDebugPrints();
        fakeAsync((async) {
          deliveringOverToDevice(async);
          async.elapse(const Duration(minutes: 1));
        });

        expect(
          reported(logs).where((l) => l.contains('deliver our sender key')),
          [startsWith('zuno/caught: deliver our sender key:')],
        );
        final retries = logs.where((l) => l.startsWith('zuno/retry:'));
        expect(retries.length, greaterThan(3));
        expect(
          retries,
          everyElement(startsWith('zuno/retry: sender key delivery ')),
        );
        expect(logs.join('\n'), isNot(contains('BOBDEVICE')));
      },
    );

    test('a delivery cut short by the call ending is not reported', () async {
      final logs = recordDebugPrints();
      final queried = Completer<void>();
      final answer = Completer<void>();
      final endingClient = buildCallTestClient((request) async {
        if (request.url.path.endsWith('/keys/query')) {
          if (!queried.isCompleted) queried.complete();
          await answer.future;
          return http.Response('boom', 500);
        }
        return http.Response('{"event_id":"\$evt"}', 200);
      });
      final endingRoom = buildTestRoom(endingClient);
      joinTheCall(
        endingRoom,
        _bob,
        deviceId: 'BOBDEVICE',
        fociActive: _encryptedFoci,
      );
      final session = incoming(
        inRoom: endingRoom,
        keyDeliveryDelay: Duration.zero,
      );

      await session.accept();
      await queried.future;
      await session.hangUp();
      answer.complete();
      await pumpEventQueue();

      expect(
        reported(logs).where((l) => l.contains('deliver our sender key')),
        isEmpty,
      );
    });

    test('a known device republishing the same created_ts is not sent our key '
        'again', () async {
      final call = keyDeliveryCall();
      void bobPublishes({required bool audioMuted}) => joinTheCall(
        call.room,
        _bob,
        deviceId: 'BOBDEVICE',
        createdAtMs: 1,
        fociActive: {..._encryptedFoci, 'audioMuted': audioMuted},
      );
      bobPublishes(audioMuted: false);
      await call.session.accept();
      await pumpEventQueue();
      expect(call.client.tries, ['BOBDEVICE']);

      bobPublishes(audioMuted: true);
      await sync(call.client);

      expect(call.client.tries, ['BOBDEVICE']);
    });

    test('a send that reaches no device for want of an Olm session is retried '
        'until one is set up, and then stops', () {
      fakeAsync((async) {
        final call = deliveringOverToDevice(
          async,
          over: ToDeviceRecordingClient()..olm = true,
        );
        async.elapse(const Duration(seconds: 8));
        expect(call.client.keysSent, isEmpty);
        expect(triesFor(call, 'BOBDEVICE'), greaterThan(3));

        call.client.openOlmSession('BOBDEVICE');
        async.elapse(const Duration(seconds: 5));

        expect(call.client.keysSent.keys, ['BOBDEVICE']);
        final tries = call.client.tries.length;
        async.elapse(const Duration(minutes: 1));
        expect(call.client.tries, hasLength(tries));
      });
    });

    test('a blocked device is never sent our key, nor chased', () {
      fakeAsync((async) {
        final call = keyDeliveryCall(
          over: ToDeviceRecordingClient()..olm = true,
        );
        call.client.userDeviceKeys[_bob]!.deviceKeys['BOBDEVICE']!.blocked =
            true;
        unawaited(call.session.accept());
        async.elapse(const Duration(minutes: 1));

        expect(call.client.tries, isEmpty);
      });
    });

    test('a device in the call that starts a new Olm session is sent our key '
        'again over it', () async {
      final call = keyDeliveryCall();
      await call.session.accept();
      await pumpEventQueue();
      expect(call.client.tries, ['BOBDEVICE']);

      call.client.onToDeviceEvent.add(dummyFrom(_bob, 'BOBDEVICE'));
      await pumpEventQueue();

      expect(call.client.tries, ['BOBDEVICE', 'BOBDEVICE']);
    });

    test('a new Olm session from a device outside the call, or a dummy that '
        'was never encrypted, sends nothing', () async {
      final call = keyDeliveryCall();
      setSelfSignedTestDevices(call.client, _mallory, ['MALDEV']);
      await call.session.accept();
      await pumpEventQueue();

      call.client.onToDeviceEvent
        ..add(dummyFrom(_mallory, 'MALDEV'))
        ..add(dummyFrom(_bob, 'BOBDEVICE', encrypted: false));
      await pumpEventQueue();

      expect(call.client.tries, ['BOBDEVICE']);
    });

    for (final (outcome, finish) in [
      (
        'fails',
        (Completer<void> send) =>
            send.completeError(http.ClientException('502 Bad Gateway')),
      ),
      ('succeeds', (Completer<void> send) => send.complete()),
    ]) {
      test('a send still out when its device re-joins neither re-arms nor '
          'ends the newer delivery when it $outcome', () {
        final logs = recordDebugPrints();
        int retriesLogged() =>
            logs.where((l) => l.startsWith('zuno/retry:')).length;
        fakeAsync((async) {
          final firstSend = Completer<void>();
          final call = deliveringOverToDevice(
            async,
            over: ToDeviceRecordingClient()..hold = firstSend,
          );
          expect(call.client.tries, ['BOBDEVICE']);

          call.client.unreachable.add('BOBDEVICE');
          joinTheCall(
            call.room,
            _bob,
            deviceId: 'BOBDEVICE',
            createdAtMs: 2,
            fociActive: _encryptedFoci,
          );
          call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
          async.flushMicrotasks();
          expect(call.client.tries, ['BOBDEVICE', 'BOBDEVICE']);
          final retries = retriesLogged();

          finish(firstSend);
          async.flushMicrotasks();
          expect(retriesLogged(), retries);

          call.client.sent.clear();
          call.client.unreachable.clear();
          async.elapse(const Duration(seconds: 5));
          expect(call.client.keysSent.keys, ['BOBDEVICE']);
          final tries = call.client.tries.length;
          async.elapse(const Duration(minutes: 1));
          expect(call.client.tries, hasLength(tries));
        });
      });
    }
  });

  group('everHadRemote / remoteJoinedStream', () {
    test('a remote membership flips it and fires the stream once, even when '
        'it is republished', () async {
      final session = incoming();
      final joins = <void>[];
      session.remoteJoinedStream.listen(joins.add);

      joinTheCall(room, _bob);
      await session.accept();
      await pumpEventQueue();
      expect(session.everHadRemote, isTrue);

      joinTheCall(room, _bob);
      await sync();

      expect(joins, hasLength(1));
    });

    test(
      'a membership for a different call is not this call answered',
      () async {
        final session = incoming();
        final joins = <void>[];
        session.remoteJoinedStream.listen(joins.add);

        joinTheCall(room, _bob, callId: 'some-other-call');
        await session.accept();
        await pumpEventQueue();

        expect(session.everHadRemote, isFalse);
        expect(joins, isEmpty);
      },
    );
  });

  test('a membership of the wrong shape never breaks the call', () async {
    final session = incoming();
    await session.accept();
    await pumpEventQueue();

    room.setState(
      buildTestEvent(
        room,
        eventId: r'$broken',
        senderId: _mallory,
        type: callMemberEventType,
        stateKey: _mallory,
        content: {
          'memberships': [<String, Object?>{}],
        },
      ),
    );
    joinTheCall(room, _bob, fociActive: {'sessionId': 7});
    await sync();

    expect(session.phase, CallSessionPhase.active);
    expect(session.everHadRemote, isTrue);
  });

  group('the start of an outgoing call', () {
    test('opens the microphone while its invite is still being sent', () async {
      final r = sendRoom()..sendGate = Completer<void>();
      final engine = FakeCallEngine();
      final session = outgoing(r, kind: CallKind.video, engine: engine);

      await pumpEventQueue();

      expect(engine.startLocalMediaCalls, 1);
      expect(engine.joined, isFalse);
      expect(r.sentEvents, isEmpty);
      r.sendGate!.complete();
      await untilPhase(session, CallSessionPhase.active);
      expect(engine.startLocalMediaCalls, 1);
    });

    test('rings nobody when the microphone is refused', () async {
      permissions.onRequest = permissionDenied;
      final r = sendRoom();
      final engine = FakeCallEngine();
      final session = outgoing(r, engine: engine);

      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      expect(r.attempts, isEmpty);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallMicrophoneUnavailable());
      expect(engine.startLocalMediaCalls, 0);
    });

    test('no invite is sent when the server offers no calls', () async {
      final logs = recordDebugPrints();
      final r = sendRoom();
      final engine = FakeCallEngine()..readyError = const CallsNotOffered();
      final session = outgoing(r, engine: engine);

      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      expect(r.requests, isEmpty);
      expect(session.failure, const CallsNotAvailable());
      expect(session.endReason, CallEndReason.failed);
      expect(engine.leaveCalls, 1);
      expect(reported(logs), isEmpty);
    });

    test('no invite is sent when discovery fails offline', () async {
      final logs = recordDebugPrints();
      final r = sendRoom();
      final engine = FakeCallEngine()
        ..readyError = http.ClientException('offline');
      final session = outgoing(r, engine: engine);

      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      expect(r.requests, isEmpty);
      expect(session.failure, const CallDidNotConnect());
      expect(session.endReason, CallEndReason.failed);
      expect(reported(logs), isEmpty);
    });

    test('microphone refusal wins over a discovery failure', () async {
      permissions.onRequest = permissionDenied;
      final r = sendRoom();
      final engine = FakeCallEngine()..readyError = const CallsNotOffered();
      final session = outgoing(r, engine: engine);

      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      expect(r.requests, isEmpty);
      expect(session.failure, const CallMicrophoneUnavailable());
    });

    test('local media opens while readiness is still pending', () async {
      final r = sendRoom();
      final engine = FakeCallEngine()..readyGate = Completer<void>();
      outgoing(r, engine: engine);

      await pumpEventQueue();

      expect(engine.startLocalMediaCalls, 1);
      expect(r.requests, isEmpty);
    });

    test('a server failure from config is not reported', () async {
      final logs = recordDebugPrints();
      final engine = FakeCallEngine()
        ..readyError = CallsModuleException(
          'HTTP 503 from GET /config',
          statusCode: 503,
        );
      final session = outgoing(sendRoom(), engine: engine);

      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failure, const CallDidNotConnect());
      expect(reported(logs), isEmpty);
    });

    test('hang up while ready() is pending sends nothing', () async {
      final r = sendRoom();
      final engine = FakeCallEngine()..readyGate = Completer<void>();
      final session = outgoing(r, engine: engine);
      await pumpEventQueue();

      await session.hangUp();
      engine.readyGate!.complete();
      await pumpEventQueue();

      expect(engine.readyCalls, 1);
      expect(r.requests, isEmpty);
      expect(engine.startLocalMediaCalls, 1);
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(session.phase, CallSessionPhase.ended);
    });

    test('an invite the server never confirms is reported as such', () async {
      final logs = recordDebugPrints();
      final session = outgoing(sendRoom()..undelivered = true);

      await untilPhase(session, CallSessionPhase.ended);

      expect(reported(logs), [
        'zuno/caught: send the call invite: '
            'Bad state: The call invite was not sent',
      ]);
    });

    test('an invite the room refuses says so and is not reported', () async {
      final logs = recordDebugPrints();
      final session = outgoing(sendRoom()..sendError = forbidden());

      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failure, const CallNoPermissionToStart());
      expect(reported(logs), isEmpty);
    });

    test('a call the room refuses once it rings says so and is not '
        'reported', () async {
      final logs = recordDebugPrints();
      final session = outgoing(
        sendRoom(),
        engine: FakeCallEngine(failJoin: true, joinError: forbidden()),
      );

      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failure, const CallNoPermissionToStart());
      expect(reported(logs), isEmpty);
    });

    test('a failure the calls module expects once it rings is not '
        'reported', () async {
      final logs = recordDebugPrints();
      final session = outgoing(
        sendRoom(),
        engine: FakeCallEngine(
          failJoin: true,
          joinError: const CallsRouteGone('POST /livekit/token'),
        ),
      );

      await untilPhase(session, CallSessionPhase.ended);

      expect(reported(logs), isEmpty);
    });

    test('an invite that fails for another reason is reported', () async {
      final logs = recordDebugPrints();
      final session = outgoing(sendRoom()..sendError = StateError('boom'));

      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failure, const CallDidNotConnect());
      expect(reported(logs), [
        'zuno/caught: start an outgoing call: Bad state: boom',
      ]);
    });

    test('an invite the server never confirms ends the call with a message, '
        'releases the microphone and rings nobody', () async {
      final r = sendRoom()..undelivered = true;
      final engine = FakeCallEngine();
      final session = outgoing(r, engine: engine);

      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallDidNotConnect());
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(engine.joined, isFalse);
      expect(r.attempts.single['msgtype'], callInviteMsgtype);
    });

    test('a call that fails to connect after ringing posts a missed call, so '
        'the other side stops ringing', () async {
      final r = sendRoom();
      final engine = FakeCallEngine(failJoin: true);
      final session = outgoing(r, kind: CallKind.video, engine: engine);

      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      final summary = CallSummary.fromEvent(
        buildTestEvent(
          r,
          eventId: r'$summary',
          senderId: _me,
          content: r.sentEvents.last,
        ),
      );
      expect(r.sentEvents.first['msgtype'], callInviteMsgtype);
      expect(summary?.status, CallSummaryStatus.missed);
      expect(summary?.callId, session.callId);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallDidNotConnect());
      expect(engine.disposeCalls, 1);
    });

    test('a call hung up before its invite is sent releases the microphone '
        'and is never joined', () async {
      final r = sendRoom()..sendGate = Completer<void>();
      final engine = FakeCallEngine();
      final session = outgoing(r, engine: engine);
      await pumpEventQueue();

      final hangingUp = session.hangUp(byUser: true);
      r.sendGate!.complete();
      await hangingUp;
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(engine.joined, isFalse);
    });
  });

  group('what an outgoing call sends', () {
    test('its invite and summary keep no local copy that could be resent '
        'once the call is over', () async {
      final r = sendRoom();
      final session = outgoing(r);
      await untilPhase(session, CallSessionPhase.active);

      await session.hangUp(byUser: true);

      expect(r.attempts.map((e) => e['msgtype']), [
        callInviteMsgtype,
        callSummaryMsgtype,
      ]);
      expect(r.pendingCopies, [false, false]);
    });

    test('nothing at all when it is hung up while the microphone prompt is '
        'still up', () async {
      final prompt = permissions.requestGate = Completer<void>();
      final memberPuts = <String>[];
      final r = sendRoom(loggingMemberPuts(memberPuts));
      final engine = FakeCallEngine();
      final session = outgoing(r, engine: engine);
      await pumpEventQueue();

      await session.hangUp(byUser: true);
      prompt.complete();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(r.attempts, isEmpty);
      expect(memberPuts, isEmpty);
      expect(engine.startLocalMediaCalls, 0);
    });

    test('a missed call once its invite lands, when hung up while the invite '
        'was still going out', () async {
      final r = sendRoom()..sendGate = Completer<void>();
      final session = outgoing(r);
      await pumpEventQueue();

      final hangingUp = session.hangUp(byUser: true);
      await pumpEventQueue();
      expect(session.phase, CallSessionPhase.ended);
      r.sendGate!.complete();
      await hangingUp;

      expect(r.sentEvents.map((e) => e['msgtype']), [
        callInviteMsgtype,
        callSummaryMsgtype,
      ]);
      expect(r.sentEvents.last['status'], CallSummaryStatus.missed.name);
    });

    test('nothing more when hung up while an invite that never lands was '
        'going out', () async {
      final r = sendRoom()
        ..sendGate = Completer<void>()
        ..undelivered = true;
      final session = outgoing(r);
      await pumpEventQueue();

      final hangingUp = session.hangUp(byUser: true);
      r.sendGate!.complete();
      await hangingUp;

      expect(r.attempts.single['msgtype'], callInviteMsgtype);
    });

    test('a video call with the camera refused goes ahead with the camera '
        'off', () async {
      permissions.onRequestOf[Permission.camera.value] = permissionDenied;
      final r = sendRoom();
      final engine = _JournalEngine(kind: CallKind.video);
      final session = outgoing(r, kind: CallKind.video, engine: engine);

      await untilPhase(session, CallSessionPhase.active);

      expect(engine.journal.take(2), ['camera false', 'local media']);
      expect(r.sentEvents.single['msgtype'], callInviteMsgtype);
      expect(session.failure, isNull);
    });

    test('leaving the room while the invite is going out ends the call '
        'without writing to it', () async {
      final memberPuts = <String>[];
      final logging = loggingMemberPuts(memberPuts);
      final r = sendRoom(logging)..sendGate = Completer<void>();
      logging.rooms.add(r);
      final session = outgoing(r);
      await pumpEventQueue();

      logging.onSync.add(
        SyncUpdate(
          nextBatch: 'left',
          rooms: RoomsUpdate(leave: {r.id: LeftRoomUpdate()}),
        ),
      );
      await pumpEventQueue();
      expect(session.phase, CallSessionPhase.ended);
      r.sendGate!.complete();
      await pumpEventQueue();

      expect(r.attempts.single['msgtype'], callInviteMsgtype);
      expect(memberPuts, isEmpty);
    });
  });

  group('the summary a caller posts', () {
    Future<String?> statusAfter(
      Future<void> Function(
        CallSession session,
        SendRecordingRoom room,
        FakeCallEngine engine,
      )
      ending, {
      Duration? ringTimeout,
    }) async {
      final r = sendRoom();
      joinMembers(r, [_me, _bob]);
      final engine = FakeCallEngine();
      final session = outgoing(r, engine: engine, ringTimeout: ringTimeout);
      await untilPhase(session, CallSessionPhase.active);
      final ended = untilPhase(session, CallSessionPhase.ended);
      await ending(session, r, engine);
      await ended;
      await pumpEventQueue();
      final summaries = r.sentEvents.where(
        (e) => e['msgtype'] == callSummaryMsgtype,
      );
      return summaries.singleOrNull?['status'] as String?;
    }

    Future<void> bobAnswersThenLeaves(CallSession session, Room r) async {
      joinTheCall(r, _bob, callId: session.callId);
      await sync();
      leaveTheCall(r, _bob);
      await sync();
    }

    test('declined when the other side declines', () async {
      final status = await statusAfter((session, r, _) async {
        client.onTimelineEvent.add(declineFrom(r, _bob, session.callId));
      });

      expect(status, CallSummaryStatus.declined.name);
    });

    test('missed when nobody answers before the ring times out', () async {
      final status = await statusAfter(
        (_, _, _) async {},
        ringTimeout: const Duration(milliseconds: 50),
      );

      expect(status, CallSummaryStatus.missed.name);
    });

    test('missed when hung up before anyone answers', () async {
      final status = await statusAfter(
        (session, _, _) => session.hangUp(byUser: true),
      );

      expect(status, CallSummaryStatus.missed.name);
    });

    test('missed when the connection fails before anyone answers', () async {
      final status = await statusAfter((_, _, engine) async {
        engine.statusController.add(CallEngineStatus.failed);
      });

      expect(status, CallSummaryStatus.missed.name);
    });

    test('ended when hung up after an answer, once the other side has '
        'gone', () async {
      final status = await statusAfter((session, r, _) async {
        await bobAnswersThenLeaves(session, r);
        await session.hangUp(byUser: true);
      });

      expect(status, CallSummaryStatus.ended.name);
    });

    test('ended when the connection fails after an answer, once the other '
        'side has gone', () async {
      final status = await statusAfter((session, r, engine) async {
        await bobAnswersThenLeaves(session, r);
        engine.statusController.add(CallEngineStatus.failed);
      });

      expect(status, CallSummaryStatus.ended.name);
    });

    test(
      'none when hung up while the other side is still in the call',
      () async {
        final status = await statusAfter((session, r, _) async {
          joinTheCall(r, _bob, callId: session.callId);
          await sync();
          await session.hangUp(byUser: true);
        });

        expect(status, isNull);
      },
    );
  });

  group('_connect key-before-join ordering', () {
    test('our first own key is set and used before join() is ever '
        'called', () async {
      final engine = _JournalEngine();

      await incoming(engine: engine).accept();

      expect(engine.journal, containsAllInOrder(['key 0', 'send 0', 'join']));
    });
  });

  group('publishing our membership', () {
    _CountingSession startCountingSessionIn(FakeAsync async) {
      final c = _PublishCountingClient();
      final engine = FakeCallEngine();
      final r = buildTestRoom(c);
      joinTheCall(r, _bob);
      final session = incoming(inRoom: r, engine: engine);
      unawaited(session.accept());
      async.elapse(Duration.zero);
      return (
        session: session,
        client: c,
        publishes: c.publishes,
        engine: engine,
      );
    }

    test('a refresh carrying nothing new does not republish', () {
      fakeAsync((async) {
        final r = startCountingSessionIn(async);
        final before = r.publishes.length;

        unawaited(r.session.refreshMembership());
        unawaited(r.session.refreshMembership());
        unawaited(r.session.refreshMembership());
        async.elapse(const Duration(milliseconds: 1400));

        expect(r.publishes.length, before);
      });
    });

    test('a refresh after a real change does republish, once', () {
      fakeAsync((async) {
        final r = startCountingSessionIn(async);
        final before = r.publishes.length;

        r.engine.micMuted = true;
        unawaited(r.session.refreshMembership());
        unawaited(r.session.refreshMembership());
        async.elapse(const Duration(milliseconds: 1400));

        expect(r.publishes.length, before + 1);
        expect(r.publishes.last, contains('"audioMuted":true'));
      });
    });

    test('a real change is published at once, and changes inside the window '
        'coalesce into one trailing publish carrying the final state', () {
      fakeAsync((async) {
        final r = startCountingSessionIn(async);
        final before = r.publishes.length;

        for (final muted in [true, false, true, false]) {
          r.engine.micMuted = muted;
          unawaited(r.session.refreshMembership());
          async.flushMicrotasks();
        }
        expect(r.publishes.length, before + 1);
        expect(r.publishes.last, contains('"audioMuted":true'));

        async.elapse(const Duration(milliseconds: 1400));

        expect(r.publishes.length, before + 2);
        expect(r.publishes.last, contains('"audioMuted":false'));
      });
    });

    test('membership is refreshed on a timer so the call never expires', () {
      fakeAsync((async) {
        final r = startCountingSessionIn(async);
        expect(r.publishes, hasLength(1));

        async.elapse(const Duration(minutes: 2));

        expect(r.publishes.length, greaterThanOrEqualTo(3));
      });
    });

    test('a membership refresh the server refuses is not an uncaught '
        'error', () {
      fakeAsync((async) {
        final r = startCountingSessionIn(async);

        r.client.refusal = forbidden();
        async.elapse(const Duration(minutes: 1));

        expect(r.publishes, hasLength(2));
        expect(r.session.phase, CallSessionPhase.active);
      });
    });
  });

  group('an outgoing call rings as soon as it has an SFU session', () {
    test('publishes its membership once the session opens, before its media '
        'is published, then again with its tracks', () async {
      final c = _PublishCountingClient();
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate);
      final session = outgoing(sendRoom(c), engine: engine);
      await pumpEventQueue();
      expect(c.publishes, isEmpty);

      engine.openSession();
      await pumpEventQueue();
      expect(c.publishes.single, contains('"sessionId":"opening-session"'));
      expect(session.phase, CallSessionPhase.connecting);

      joinGate.complete();
      await untilPhase(session, CallSessionPhase.active);

      expect(c.publishes, hasLength(2));
      expect(c.publishes.last, contains('"audio":"audio"'));
    });

    test('a caller who may not start calls is told so, and the early write\'s '
        'refusal is not reported', () async {
      final logs = recordDebugPrints();
      final c = _PublishCountingClient()..refusal = forbidden();
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate);
      final session = outgoing(sendRoom(c), engine: engine);
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();
      joinGate.complete();
      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failure, const CallNoPermissionToStart());
      expect(
        reported(logs).where((line) => line.contains('refresh membership')),
        isEmpty,
      );
    });

    test('a membership write refused for a defect in our own event is '
        'reported', () async {
      final logs = recordDebugPrints();
      final c = _PublishCountingClient()..refusal = badJson();
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate);
      final session = outgoing(sendRoom(c), engine: engine);
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();
      joinGate.complete();
      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failure, const CallDidNotConnect());
      expect(
        reported(logs).where((line) => line.contains('M_BAD_JSON')),
        isNotEmpty,
      );
    });

    test('a caller whose join fails after the callee started ringing takes '
        'its membership back and sends the call summary', () async {
      final c = _PublishCountingClient();
      final r = sendRoom(c);
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate, failJoin: true);
      final session = outgoing(r, engine: engine);
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();
      expect(c.publishes.single, contains('"sessionId":"opening-session"'));

      joinGate.complete();
      await untilPhase(session, CallSessionPhase.ended);
      await pumpEventQueue();

      expect(c.publishes.last, contains('"memberships":[]'));
      expect(r.attempts.map((e) => e['msgtype']), [
        callInviteMsgtype,
        callSummaryMsgtype,
      ]);
    });

    test('rings while its microphone and camera are still opening', () async {
      final c = _PublishCountingClient();
      final engine = _OpeningSessionEngine(joinGate: Completer<void>())
        ..startGate = Completer<void>();
      outgoing(sendRoom(c), engine: engine);
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();

      expect(engine.startLocalMediaCalls, 1);
      expect(c.publishes.single, contains('"sessionId":"opening-session"'));
    });

    test('a session that opens as the caller hangs up publishes '
        'nothing', () async {
      final c = _PublishCountingClient();
      final engine = _OpeningSessionEngine(joinGate: Completer<void>());
      final session = outgoing(sendRoom(c), engine: engine);
      await pumpEventQueue();

      unawaited(session.hangUp());
      engine.openSession();
      await pumpEventQueue();

      expect(c.publishes.where((p) => p.contains('opening-session')), isEmpty);
    });
  });

  group('an answered call joins as soon as it has an SFU session', () {
    test('publishes its membership once the session opens, before its media '
        'is published, then again with its tracks', () async {
      final c = _PublishCountingClient();
      final r = buildTestRoom(c);
      joinTheCall(r, _caller, deviceId: 'CALLERDEV');
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate);
      final session = incoming(inRoom: r, engine: engine);
      final accepting = session.accept();
      await pumpEventQueue();
      expect(c.publishes, isEmpty);

      engine.openSession();
      await pumpEventQueue();
      expect(c.publishes.single, contains('"sessionId":"opening-session"'));
      expect(session.phase, CallSessionPhase.connecting);

      joinGate.complete();
      await accepting;

      expect(session.phase, CallSessionPhase.active);
      expect(c.publishes, hasLength(2));
      expect(c.publishes.last, contains('"audio":"audio"'));
    });

    test(
      'takes in the caller and sends it our key as soon as its session '
      'opens, before the join finishes, and follows each sync once',
      () async {
        final joinGate = Completer<void>();
        final engine = _OpeningSessionEngine(joinGate: joinGate);
        final call = keyDeliveryCall(
          inCall: const {_caller: 'CALLERDEV'},
          engine: engine,
          keyDeliveryDelay: Duration.zero,
        );
        final accepting = call.session.accept();
        await pumpEventQueue();
        expect(engine.updatedRemotes, isEmpty);

        engine.openSession();
        await pumpEventQueue();
        expect(engine.updatedRemotes, [_callerDevice]);
        expect(call.client.keysSent.keys, ['CALLERDEV']);
        expect(call.session.phase, CallSessionPhase.connecting);

        joinGate.complete();
        await accepting;
        final seen = engine.updatedRemotes.length;
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        await pumpEventQueue();
        expect(engine.updatedRemotes, hasLength(seen + 1));
      },
    );

    test('a session that opens as the callee hangs up takes in no '
        'one', () async {
      final engine = _OpeningSessionEngine(joinGate: Completer<void>());
      final call = keyDeliveryCall(
        inCall: const {_caller: 'CALLERDEV'},
        engine: engine,
        keyDeliveryDelay: Duration.zero,
      );
      unawaited(call.session.accept());
      await pumpEventQueue();

      unawaited(call.session.hangUp());
      engine.openSession();
      await pumpEventQueue();

      expect(engine.updatedRemotes, isEmpty);
      expect(call.client.keysSent, isEmpty);
    });

    test('answers while its microphone and camera are still opening', () async {
      final c = _PublishCountingClient();
      final r = buildTestRoom(c);
      joinTheCall(r, _caller, deviceId: 'CALLERDEV');
      final joinGate = Completer<void>();
      final startGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate)
        ..startGate = startGate;
      final session = incoming(inRoom: r, engine: engine);
      final accepting = session.accept();
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();
      expect(engine.startLocalMediaCalls, 1);
      expect(c.publishes.single, contains('"sessionId":"opening-session"'));

      joinGate.complete();
      await pumpEventQueue();
      expect(session.phase, CallSessionPhase.connecting);

      startGate.complete();
      await accepting;
      expect(session.phase, CallSessionPhase.active);
    });

    test('a microphone that fails to open after the session opened fails the '
        'call and takes the membership back', () async {
      final c = _PublishCountingClient();
      final r = sendRoom(c);
      joinTheCall(r, _caller, deviceId: 'CALLERDEV');
      final startGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: Completer<void>())
        ..startGate = startGate;
      final session = incoming(inRoom: r, engine: engine);
      final accepting = session.accept();
      await pumpEventQueue();
      engine.openSession();
      await pumpEventQueue();

      startGate.completeError(StateError('the microphone is busy'));
      await expectLater(accepting, throwsStateError);
      await session.hangUpFinished;

      expect(session.phase, CallSessionPhase.ended);
      expect(session.failure, const CallDidNotConnect());
      expect(c.publishes.last, contains('"memberships":[]'));
      expect(engine.leaveCalls, 1);
    });

    test('a callee whose join fails after its session opened takes its '
        'membership back, and posts nothing while the caller is still '
        'there', () async {
      final c = _PublishCountingClient();
      final r = sendRoom(c);
      joinTheCall(r, _caller, deviceId: 'CALLERDEV');
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate, failJoin: true);
      final session = incoming(inRoom: r, engine: engine);
      final accepting = session.accept();
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();
      joinGate.complete();
      await expectLater(accepting, throwsStateError);
      await session.hangUpFinished;

      expect(session.phase, CallSessionPhase.ended);
      expect(c.publishes.last, contains('"memberships":[]'));
      expect(r.attempts, isEmpty);
    });
  });

  group('our membership while we join', () {
    test('a key the caller sends in reply to our first membership is loaded '
        'while we still join', () async {
      late final Client logging;
      final published = <String>[];
      logging = loggingMemberPuts(
        published,
        onPut: (_) async {
          logging.onToDeviceEvent.add(keyEvent());
          return null;
        },
      );
      final r = buildTestRoom(logging);
      setSelfSignedTestDevices(logging, _caller, ['CALLERDEV']);
      joinTheCall(r, _caller, deviceId: 'CALLERDEV');
      final joinGate = Completer<void>();
      final engine = _OpeningSessionEngine(joinGate: joinGate);
      final session = incoming(inRoom: r, engine: engine);
      final accepting = session.accept();
      await pumpEventQueue();

      engine.openSession();
      await pumpEventQueue();

      expect(published, hasLength(1));
      expect(session.phase, CallSessionPhase.connecting);
      expect(engine.peerKeys[_callerDevice], {0: testKey()});

      joinGate.complete();
      await accepting;
    });

    test('a callee whose membership write fails clears it on the way out, '
        'so nobody waits on a ghost', () async {
      final memberPuts = <String>[];
      final refusing = loggingMemberPuts(
        memberPuts,
        onPut: (_) async => memberPuts.length == 1
            ? http.Response('{"errcode":"M_UNKNOWN","error":"later"}', 500)
            : null,
      );
      final session = incoming(inRoom: sendRoom(refusing));

      await expectLater(session.accept(), throwsA(isA<MatrixException>()));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(memberPuts, hasLength(2));
      expect(memberPuts.last, contains('"memberships":[]'));
    });

    test('the next call in the same room publishes only after the last '
        "call's membership clear has gone out", () async {
      final clearGate = Completer<void>();
      final memberPuts = <String>[];
      final gated = loggingMemberPuts(
        memberPuts,
        onPut: (body) async {
          if (body.contains('"memberships":[]')) await clearGate.future;
          return null;
        },
      );

      final first = incoming(inRoom: sendRoom(gated), callId: 'first');
      await first.accept();
      final hangingUp = first.hangUp(byUser: true);
      await pumpEventQueue();
      expect(first.phase, CallSessionPhase.ended);

      final second = incoming(inRoom: sendRoom(gated), callId: 'second');
      final accepting = second.accept();
      await pumpEventQueue();
      expect(memberPuts, hasLength(2));

      clearGate.complete();
      await accepting;
      await hangingUp;

      expect(memberPuts, hasLength(3));
      expect(memberPuts[1], contains('"memberships":[]'));
      expect(memberPuts[2], contains('"call_id":"second"'));
      expect(second.phase, CallSessionPhase.active);
    });
  });

  group('ending a call', () {
    _RoomCall buildActiveCall() {
      final r = sendRoom();
      final engine = FakeCallEngine();
      return (
        session: incoming(inRoom: r, engine: engine),
        engine: engine,
        room: r,
      );
    }

    int summariesIn(SendRecordingRoom room) => room.sentEvents
        .where((content) => content['msgtype'] == callSummaryMsgtype)
        .length;

    test('the clear a hang-up writes names the call it leaves', () async {
      final memberPuts = <String>[];
      final session = incoming(
        inRoom: sendRoom(loggingMemberPuts(memberPuts)),
        engine: FakeCallEngine(),
      );
      await session.accept();

      await session.hangUp(byUser: true);

      expect(jsonDecode(memberPuts.last), {
        'memberships': <Object?>[],
        'left_call_id': 'call1',
      });
    });

    test('the call says it is ending as soon as a hang-up starts, before '
        'the teardown finishes', () async {
      final engine = FakeCallEngine()..leaveGate = Completer<void>();
      final session = incoming(inRoom: sendRoom(), engine: engine);
      await session.accept();
      var endingStarted = false;
      unawaited(session.endingStarted.then((_) => endingStarted = true));

      final hangingUp = session.hangUp();
      await pumpEventQueue();

      expect(endingStarted, isTrue);
      expect(session.ending, isTrue);
      expect(session.phase, CallSessionPhase.active);
      engine.leaveGate!.complete();
      await hangingUp;
    });

    test('a call ending because its room was left says it is ending before '
        'the teardown finishes', () async {
      final engine = FakeCallEngine()..leaveGate = Completer<void>();
      final r = sendRoom();
      final session = incoming(inRoom: r, engine: engine);
      await session.accept();

      client.onSync.add(
        SyncUpdate(
          nextBatch: 'next',
          rooms: RoomsUpdate(leave: {r.id: LeftRoomUpdate()}),
        ),
      );
      await pumpEventQueue();

      expect(session.ending, isTrue);
      expect(session.phase, CallSessionPhase.active);
      engine.leaveGate!.complete();
      await pumpEventQueue();
      expect(session.phase, CallSessionPhase.ended);
    });

    test('the end button marks the hang-up as the user\'s own', () async {
      final call = buildActiveCall();
      await call.session.accept();

      await call.session.hangUp(byUser: true);

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.session.endedByUser, isTrue);
    });

    test('the first hang-up decides who ended the call', () async {
      final call = buildActiveCall();
      await call.session.accept();

      await Future.wait([
        call.session.hangUp(),
        call.session.hangUp(byUser: true),
      ]);

      expect(call.session.endedByUser, isFalse);
      expect(summariesIn(call.room), 1);
    });

    test('a hang-up for a call its caller already summarised sends no summary '
        'of its own', () async {
      final call = buildActiveCall();
      await call.session.accept();

      await call.session.hangUp(summarized: true);

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.session.endReason, CallEndReason.missed);
      expect(call.engine.leaveCalls, 1);
      expect(summariesIn(call.room), 0);
    });

    test('the first hang-up decides whether the call was already '
        'summarised', () async {
      final summarisedFirst = buildActiveCall();
      final plainFirst = buildActiveCall();
      for (final call in [summarisedFirst, plainFirst]) {
        await call.session.accept();
      }

      await Future.wait([
        summarisedFirst.session.hangUp(summarized: true),
        summarisedFirst.session.hangUp(),
      ]);
      await Future.wait([
        plainFirst.session.hangUp(),
        plainFirst.session.hangUp(summarized: true),
      ]);

      expect(summariesIn(summarisedFirst.room), 0);
      expect(summariesIn(plainFirst.room), 1);
    });

    test('hang-ups landing at once or after the call ended tear it down and '
        'summarise it exactly once', () async {
      final call = buildActiveCall();
      await call.session.accept();

      await expectLater(
        Future.wait([call.session.hangUp(), call.session.hangUp()]),
        completes,
      );
      await call.session.hangUp();
      await pumpEventQueue();

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.engine.leaveCalls, 1);
      expect(call.engine.disposeCalls, 1);
      expect(summariesIn(call.room), 1);
    });

    test(
      'a hang-up resuming after the engine is disposed never reaches it',
      () async {
        final firstClearArrived = Completer<void>();
        final releaseFirstClear = Completer<void>();
        final memberPuts = <String>[];
        final gated = loggingMemberPuts(
          memberPuts,
          onPut: (body) async {
            if (body.contains('"memberships":[]') &&
                !firstClearArrived.isCompleted) {
              firstClearArrived.complete();
              await releaseFirstClear.future;
            }
            return null;
          },
        );
        final r = sendRoom(gated);
        final engine = FakeCallEngine();
        final session = incoming(inRoom: r, engine: engine);
        await session.accept();

        final first = session.hangUp();
        await firstClearArrived.future;

        final second = session.hangUp();
        await pumpEventQueue();

        releaseFirstClear.complete();
        await expectLater(Future.wait([first, second]), completes);
        await pumpEventQueue();

        expect(
          memberPuts.where((body) => body.contains('"memberships":[]')),
          hasLength(1),
        );
        expect(engine.leaveCalls, 1);
        expect(engine.disposeCalls, 1);
        expect(summariesIn(r), 1);
      },
    );

    for (final (stage, heldBy) in [
      (
        'the microphone is still opening',
        (Completer<void> gate) => _JournalEngine()..startGate = gate,
      ),
      (
        'the engine is still joining',
        (Completer<void> gate) => _JournalEngine(joinGate: gate),
      ),
    ]) {
      test('a hang-up while $stage tears the engine down and goes no further: '
          'no membership, and a decline rather than a summary', () async {
        final memberPuts = <String>[];
        final r = sendRoom(loggingMemberPuts(memberPuts));
        final gate = Completer<void>();
        final engine = heldBy(gate);
        final session = incoming(inRoom: r, engine: engine);

        final accepting = session.accept();
        await pumpEventQueue();
        await session.hangUp();
        gate.complete();
        await accepting;
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(
          engine.journal,
          unorderedEquals(['local media', 'key 0', 'send 0', 'join']),
        );
        expect(engine.leaveCalls, 1);
        expect(engine.disposeCalls, 1);
        expect(memberPuts, isEmpty);
        expect(summariesIn(r), 0);
        expect(r.sentEvents.single['msgtype'], callDeclineMsgtype);
      });
    }
  });

  group('auto-hangup when the remote membership reads empty', () {
    Future<_RoomCall> startJoinedCall() async {
      final r = sendRoom();
      joinTheCall(r, _bob, deviceId: 'BOBDEVICE');
      final engine = FakeCallEngine();
      final session = incoming(inRoom: r, engine: engine);
      await session.accept();
      await pumpEventQueue();
      expect(
        session.everHadRemote,
        isTrue,
        reason: 'setup: the initial reconcile pass should have seen Bob',
      );
      return (session: session, engine: engine, room: r);
    }

    _CountingSession startJoinedCallIn(FakeAsync async) {
      final c = _PublishCountingClient();
      final r = sendRoom(c);
      joinTheCall(r, _bob, deviceId: 'BOBDEVICE');
      final engine = FakeCallEngine();
      final session = incoming(inRoom: r, engine: engine);
      unawaited(session.accept());
      async.elapse(Duration.zero);
      expect(session.everHadRemote, isTrue);
      leaveTheCall(r, _bob);
      c.onSync.add(SyncUpdate(nextBatch: 'empty'));
      async.flushMicrotasks();
      return (
        session: session,
        client: c,
        publishes: c.publishes,
        engine: engine,
      );
    }

    test('the summary of this answered call references this device\'s '
        'membership, so it does not push', () async {
      final call = await startJoinedCall();

      leaveTheCall(call.room, _bob);
      await sync();
      await sync();

      final summary = call.room.sentEvents.singleWhere(
        (content) => content['msgtype'] == callSummaryMsgtype,
      );
      expect(summary['status'], CallSummaryStatus.ended.name);
      expect(summary['m.relates_to'], {
        'rel_type': 'm.reference',
        'event_id': r'$evt',
      });
    });

    test('hangs up once the empty reconciliation is confirmed on a second '
        'consecutive pass', () async {
      final call = await startJoinedCall();

      leaveTheCall(call.room, _bob);
      await sync();
      await sync();

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.engine.leaveCalls, 1);
    });

    test('does not hang up on a single empty pass, and confirms it on a '
        'timer, so a hang-up is noticed without waiting for unrelated sync '
        'traffic', () {
      fakeAsync((async) {
        final call = startJoinedCallIn(async);
        expect(call.session.phase, CallSessionPhase.active);
        expect(call.engine.leaveCalls, 0);

        async.elapse(const Duration(seconds: 5));

        expect(call.session.phase, CallSessionPhase.ended);
        expect(call.engine.leaveCalls, 1);
      });
    });

    test('a remote that reappears before the timer fires cancels the '
        'confirmation', () {
      fakeAsync((async) {
        final call = startJoinedCallIn(async);

        joinTheCall(call.session.room, _bob, deviceId: 'BOBDEVICE');
        call.client.onSync.add(SyncUpdate(nextBatch: 'back'));
        async.elapse(const Duration(seconds: 5));

        expect(call.session.phase, CallSessionPhase.active);
        expect(call.engine.leaveCalls, 0);
      });
    });

    test('does not hang up if the remote reappears between two empty passes '
        '— the exact republish-race this guards against', () async {
      final call = await startJoinedCall();

      leaveTheCall(call.room, _bob);
      await sync();
      joinTheCall(call.room, _bob, deviceId: 'BOBDEVICE');
      await sync();
      leaveTheCall(call.room, _bob);
      await sync();

      expect(call.session.phase, CallSessionPhase.active);
      expect(call.engine.leaveCalls, 0);
    });

    test('a remote that hangs up ends the call on the first pass that shows '
        'it, with no confirmation wait', () async {
      final call = await startJoinedCall();

      hangUpFromCall(call.room, userId: _bob, callId: 'call1');
      await sync();

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.session.endReason, CallEndReason.hungUp);
      expect(call.engine.leaveCalls, 1);
    });

    test('a clear naming another call still waits for confirmation, since '
        'it can be a late write from an earlier call', () async {
      final call = await startJoinedCall();

      hangUpFromCall(call.room, userId: _bob, callId: 'an-earlier-call');
      await sync();

      expect(call.session.phase, CallSessionPhase.active);
      expect(call.engine.leaveCalls, 0);
    });

    test(
      'one person hanging up leaves the call running for the rest',
      () async {
        final r = sendRoom();
        joinTheCall(r, _bob, deviceId: 'BOBDEVICE');
        joinTheCall(r, _carol, deviceId: 'CAROLDEVICE');
        final engine = FakeCallEngine();
        final session = incoming(inRoom: r, engine: engine);
        await session.accept();
        await pumpEventQueue();

        hangUpFromCall(r, userId: _carol, callId: 'call1');
        await sync();
        await sync();

        expect(session.phase, CallSessionPhase.active);
        expect(engine.leaveCalls, 0);
      },
    );
  });

  group('a call already taken on another of my devices', () {
    test('is refused with a message, writing nothing that would push that '
        'device out', () async {
      final memberPuts = <String>[];
      final r = sendRoom(loggingMemberPuts(memberPuts));
      joinTheCall(r, _me, deviceId: 'TABLET');
      final engine = FakeCallEngine();
      final session = incoming(inRoom: r, engine: engine);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failure, const CallOnAnotherDevice());
      expect(engine.joined, isFalse);
      expect(memberPuts, isEmpty);
      expect(r.attempts, isEmpty);
    });

    test('an engine asked for after the refusal is released at once', () async {
      final r = sendRoom();
      joinTheCall(r, _me, deviceId: 'TABLET');
      final engine = FakeCallEngine();
      final session = incoming(inRoom: r, engine: engine);
      await session.accept();

      expect(session.engine, same(engine));
      await pumpEventQueue();

      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
    });

    test('a membership this device left behind does not count', () async {
      final r = sendRoom();
      joinTheCall(r, _me, deviceId: 'TESTDEVICE');
      final session = incoming(inRoom: r);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });
  });

  group('a call the module says is full', () {
    test('ends as full with the module\'s own limit, reported nowhere, and '
        'releases its engine', () async {
      final logs = recordDebugPrints();
      final engine = FakeCallEngine(
        failJoin: true,
        joinError: const CallFullException(8),
      );
      final session = incoming(engine: engine);

      await expectLater(session.accept(), throwsA(isA<CallFullException>()));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(
        session.failure,
        isA<CallFull>().having((f) => f.maxParticipants, 'limit', 8),
      );
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(reported(logs), isEmpty);
    });

    test('a CallFullException from the media engine still ends as full with '
        'the module\'s limit', () async {
      recordMethodChannel(
        'FlutterWebRTC.Method',
        reply: (call) => switch (call.method) {
          'getUserMedia' => {
            'streamId': 'fake-stream',
            'audioTracks': [],
            'videoTracks': [],
          },
          'createLocalMediaStream' => {'streamId': 'local-stream'},
          'frameCryptorFactoryCreateKeyProvider' => {'keyProviderId': 'kp'},
          _ => null,
        },
      );
      final connections = FakeCallConnections()
        ..openError = const CallFullException(8);
      final session = CallSession.forIncoming(
        connections: connections,
        room: room,
        callId: 'call1',
        kind: CallKind.voice,
      );
      addTearDown(session.dispose);

      await expectLater(session.accept(), throwsA(isA<CallFullException>()));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(
        session.failure,
        isA<CallFull>().having((f) => f.maxParticipants, 'limit', 8),
      );
    });

    test('sends no decline, so its other phones are not stopped', () async {
      final r = sendRoom();
      final session = incoming(
        inRoom: r,
        engine: FakeCallEngine(
          failJoin: true,
          joinError: const CallFullException(8),
        ),
      );

      await expectLater(session.accept(), throwsA(isA<CallFullException>()));
      await pumpEventQueue();

      expect(r.sentEvents, isEmpty);
      expect(r.attempts, isEmpty);
    });

    test('a call with many people in it is still answered when the module '
        'lets it through', () async {
      for (var i = 1; i <= 10; i++) {
        joinTheCall(room, '@p$i:example.org');
      }
      final session = incoming();

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(session.failure, isNull);
    });
  });

  group('the published membership', () {
    test('keeps one join time across republishes', () async {
      final publishes = <String>[];
      final engine = FakeCallEngine();
      final session = incoming(
        inRoom: buildTestRoom(loggingMemberPuts(publishes)),
        engine: engine,
      );
      await session.accept();
      await pumpEventQueue();

      engine.micMuted = true;
      await session.refreshMembership();
      await pumpEventQueue();

      expect(publishes, hasLength(2));
      expect(_publishedJoinTime(publishes.first), greaterThan(0));
      expect(
        _publishedJoinTime(publishes.last),
        _publishedJoinTime(publishes.first),
      );
    });
  });

  group('a callee nobody joined', () {
    Event summaryOf(Room r, String callId) => buildTestEvent(
      r,
      eventId: '\$summary-$callId-${r.id}',
      senderId: _bob,
      content: CallSummary(
        callId: callId,
        kind: 'voice',
        status: CallSummaryStatus.missed,
        durationMs: 0,
      ).toMessageContent(),
    );

    int summariesIn(SendRecordingRoom r) => r.sentEvents
        .where((content) => content['msgtype'] == callSummaryMsgtype)
        .length;

    test('hangs up once its call is summarised, posting no summary of its '
        'own', () async {
      final r = sendRoom();
      final session = incoming(inRoom: r);
      await session.accept();
      await pumpEventQueue();

      client.onTimelineEvent.add(summaryOf(r, 'call1'));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endedByUser, isFalse);
      expect(summariesIn(r), 0);
    });

    test('only counts a summary of its own call in its own room', () async {
      final r = sendRoom();
      final session = incoming(inRoom: r);
      await session.accept();
      await pumpEventQueue();

      client.onTimelineEvent.add(summaryOf(r, 'call2'));
      client.onTimelineEvent.add(
        summaryOf(buildTestRoom(client, id: '!other:example.org'), 'call1'),
      );
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });

    test('is left alone by the summary once someone joined', () async {
      final r = sendRoom();
      joinTheCall(r, _bob);
      final session = incoming(inRoom: r);
      await session.accept();
      await pumpEventQueue();
      expect(session.everHadRemote, isTrue);

      client.onTimelineEvent.add(summaryOf(r, 'call1'));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });

    test('rule does not apply to a caller', () async {
      final r = sendRoom();
      final session = outgoing(r);
      await untilPhase(session, CallSessionPhase.active);

      client.onTimelineEvent.add(summaryOf(r, session.callId));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });
  });

  group('a call answered over another', () {
    test('opens its microphone and camera only once the call it replaced has '
        'let go of them', () async {
      final released = Completer<void>();
      final engine = FakeCallEngine();
      final session = incoming(
        engine: engine,
        previousCallReleased: released.future,
      );

      unawaited(session.accept());
      await pumpEventQueue();
      expect(engine.startLocalMediaCalls, 0);

      released.complete();
      await pumpEventQueue();
      expect(engine.startLocalMediaCalls, 1);
    });

    test('joins without waiting for the call it replaced to let go of the '
        'microphone and camera', () async {
      final released = Completer<void>();
      final engine = FakeCallEngine();
      final session = incoming(
        engine: engine,
        previousCallReleased: released.future,
      );

      unawaited(session.accept());
      await pumpEventQueue();

      expect(engine.joined, isTrue);
      expect(engine.startLocalMediaCalls, 0);
      released.complete();
    });

    test('stops waiting on a call that never lets go', () {
      fakeAsync((async) {
        final engine = FakeCallEngine();
        final session = incoming(
          engine: engine,
          previousCallReleased: Completer<void>().future,
        );

        unawaited(session.accept());
        async.elapse(previousCallReleaseWait - const Duration(seconds: 1));
        expect(engine.startLocalMediaCalls, 0);

        async.elapse(const Duration(seconds: 1));
        expect(engine.startLocalMediaCalls, 1);
      });
    });

    test('hung up while it waits never opens them', () async {
      final released = Completer<void>();
      final engine = FakeCallEngine();
      final session = incoming(
        engine: engine,
        previousCallReleased: released.future,
      );
      unawaited(session.accept().catchError((Object _) {}));
      await pumpEventQueue();

      await session.hangUp();
      released.complete();
      await pumpEventQueue();

      expect(engine.startLocalMediaCalls, 0);
    });

    test('a hang-up lets go of the device the next call waits on', () async {
      final leaveGate = Completer<void>();
      final session = incoming(engine: FakeCallEngine()..leaveGate = leaveGate);
      await session.accept();
      var released = false;

      unawaited(session.hangUp());
      unawaited(session.engineReleased.then((_) => released = true));
      await pumpEventQueue();
      expect(released, isFalse);

      leaveGate.complete();
      await pumpEventQueue();
      expect(released, isTrue);
    });
  });

  group('the empty call timeout', () {
    test('hangs up a callee still alone that long after the call went live, '
        'not counting the time spent connecting', () {
      fakeAsync((async) {
        final joinGate = Completer<void>();
        final session = incoming(
          inRoom: sendRoom(_PublishCountingClient()),
          engine: FakeCallEngine(joinGate: joinGate),
        );
        unawaited(session.accept());
        async.elapse(emptyCallTimeout * 2);
        expect(session.phase, CallSessionPhase.connecting);

        joinGate.complete();
        async.elapse(emptyCallTimeout - const Duration(seconds: 1));
        expect(session.phase, CallSessionPhase.active);

        async.elapse(const Duration(seconds: 1));
        expect(session.phase, CallSessionPhase.ended);
        expect(session.endedByUser, isFalse);
      });
    });

    test('keeps a callee someone joined before it ran out', () {
      fakeAsync((async) {
        final c = _PublishCountingClient();
        final r = sendRoom(c);
        final session = incoming(inRoom: r);
        unawaited(session.accept());
        async.elapse(emptyCallTimeout - const Duration(seconds: 1));
        expect(session.phase, CallSessionPhase.active);

        joinTheCall(r, _bob);
        c.onSync.add(SyncUpdate(nextBatch: 'joined'));
        async.elapse(emptyCallTimeout * 2);

        expect(session.phase, CallSessionPhase.active);
      });
    });

    test('never applies to a caller, which has its ring timeout instead', () {
      fakeAsync((async) {
        final session = outgoing(
          sendRoom(_PublishCountingClient()),
          ringTimeout: emptyCallTimeout * 4,
        );
        async.elapse(emptyCallTimeout * 2);

        expect(session.phase, CallSessionPhase.active);
      });
    });
  });

  group('ringing and declines', () {
    Future<CallSession> ringing(SendRecordingRoom r) async {
      final session = outgoing(r);
      await untilPhase(session, CallSessionPhase.active);
      return session;
    }

    test(
      'one person declining a room call keeps it ringing for the rest',
      () async {
        final r = sendRoom();
        joinMembers(r, [_me, _bob, '@carol:example.org']);
        final session = await ringing(r);

        client.onTimelineEvent.add(declineFrom(r, _bob, session.callId));
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.active);
      },
    );

    test('a decline of some other call is ignored', () async {
      final r = sendRoom();
      joinMembers(r, [_me, _bob]);
      final session = await ringing(r);

      client.onTimelineEvent.add(declineFrom(r, _bob, 'another-call'));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });

    test('a decline is ignored once someone has joined the call', () async {
      final r = sendRoom();
      joinMembers(r, [_me, _bob]);
      final session = await ringing(r);
      joinTheCall(r, _bob, callId: session.callId);
      await sync();
      expect(session.everHadRemote, isTrue);

      client.onTimelineEvent.add(declineFrom(r, _bob, session.callId));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });

    test('our own decline echoed back does not end the call', () async {
      final r = sendRoom();
      joinMembers(r, [_me, _bob]);
      final session = await ringing(r);

      client.onTimelineEvent.add(declineFrom(r, _me, session.callId));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
    });

    test('a call hung up while it connects leaves no ring timeout behind', () {
      fakeAsync((async) {
        final joinGate = Completer<void>();
        final session = outgoing(
          sendRoom(_PublishCountingClient()),
          engine: FakeCallEngine(joinGate: joinGate),
        );
        async.flushMicrotasks();
        unawaited(session.hangUp(byUser: true));
        async.flushMicrotasks();

        joinGate.complete();
        async.flushMicrotasks();

        expect(session.phase, CallSessionPhase.ended);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('someone joining stops the ring timeout', () {
      fakeAsync((async) {
        final c = _PublishCountingClient();
        final r = sendRoom(c);
        final session = outgoing(r);
        async.elapse(Duration.zero);
        expect(session.phase, CallSessionPhase.active);

        joinTheCall(r, _bob, callId: session.callId);
        c.onSync.add(SyncUpdate(nextBatch: 'answered'));
        async.elapse(const Duration(minutes: 1));

        expect(session.phase, CallSessionPhase.active);
      });
    });

    void othersInCall(Room r) {
      joinTheCall(r, '@ann:example.org', deviceId: 'ANN');
      joinTheCall(r, _bob, deviceId: 'BOB');
    }

    test('a joiner who backs out while others are in the call posts no '
        'summary', () async {
      final r = sendRoom();
      othersInCall(r);
      final joinGate = Completer<void>();
      final session = incoming(
        inRoom: r,
        engine: FakeCallEngine(joinGate: joinGate),
      );
      final accepting = session.accept();
      await pumpEventQueue();

      await session.hangUp(byUser: true);
      joinGate.complete();
      await accepting;

      expect(
        r.sentEvents.where((e) => e['msgtype'] == callSummaryMsgtype),
        isEmpty,
      );
    });

    test('a joiner who hangs up while its own membership is going out posts '
        'no summary while others are in the call', () async {
      final publishGate = Completer<void>();
      final r = sendRoom(
        loggingMemberPuts(
          [],
          onPut: (_) async {
            await publishGate.future;
            return null;
          },
        ),
      );
      othersInCall(r);
      final session = incoming(inRoom: r);
      final accepting = session.accept();
      await pumpEventQueue();

      final hangingUp = session.hangUp(byUser: true);
      await pumpEventQueue();
      publishGate.complete();
      await Future.wait([accepting, hangingUp]);

      expect(r.attempts, isEmpty);
    });
  });

  test('the engine is built against the Synapse module with the Matrix '
      'token, for this room\'s call', () async {
    const base = '/_synapse/client/zuno/calls/cloudflare';
    recordMethodChannel(
      'FlutterWebRTC.Method',
      reply: (call) {
        switch (call.method) {
          case 'createPeerConnection':
            throw PlatformException(
              code: 'test',
              message: 'no native WebRTC in tests',
            );
          case 'getUserMedia':
            return {
              'streamId': 'fake-stream',
              'audioTracks': [],
              'videoTracks': [],
            };
          case 'createLocalMediaStream':
            return {'streamId': 'local-stream'};
          case 'frameCryptorFactoryCreateKeyProvider':
            return {'keyProviderId': 'kp'};
          default:
            return null;
        }
      },
    );
    final requests = <http.Request>[];
    final module = FakeHttpClient((request) async {
      requests.add(request);
      if (request.url.path == '$base/turn/credentials') {
        return http.Response(jsonEncode({'iceServers': []}), 200);
      }
      return http.Response(jsonEncode({'sessionId': 's1'}), 200);
    });
    client.homeserver = Uri.parse('https://example.org');
    final session = CallSession.forIncoming(
      connections: CallConnections(
        client: client,
        discovery: FakeCallProviderDiscovery(),
        httpClient: module,
      ),
      room: room,
      callId: 'call1',
      kind: CallKind.voice,
      callsHttpClient: module,
    );
    addTearDown(session.dispose);

    await expectLater(session.accept(), throwsA(isA<PlatformException>()));

    expect(requests.map((r) => r.url.path).toSet(), {
      '$base/turn/credentials',
      '$base/sessions/new',
    });
    expect(requests.map((r) => r.headers['Authorization']).toSet(), {
      'Bearer test-token',
    });
    final opened = requests.singleWhere(
      (r) => r.url.path == '$base/sessions/new',
    );
    expect(opened.url.queryParameters, {
      'room_id': room.id,
      'call_id': 'call1',
    });
  });

  group('the call follows its room and the sign-in', () {
    Future<(CallSession, FakeCallEngine)> activeIn(Room callRoom) async {
      final engine = FakeCallEngine();
      final session = incoming(inRoom: callRoom, engine: engine);
      await session.accept();
      await pumpEventQueue();
      expect(session.phase, CallSessionPhase.active);
      return (session, engine);
    }

    test('each membership a remote publishes reaches the engine with its '
        'own event', () async {
      client.rooms.add(room);
      final (_, engine) = await activeIn(room);

      joinTheCall(
        room,
        '@ann:example.org',
        deviceId: 'ANN',
        fociActive: {'sessionId': 'remote'},
        eventId: r'$first',
      );
      await sync();
      expect(engine.updatedMembershipEventIds.last, r'$first');

      joinTheCall(
        room,
        '@ann:example.org',
        deviceId: 'ANN',
        fociActive: {'sessionId': 'remote'},
        eventId: r'$refreshed',
      );
      await sync();
      expect(engine.updatedMembershipEventIds.last, r'$refreshed');
    });

    test('a cache rebuild mid-call keeps following the rebuilt room', () async {
      client.rooms.add(room);
      final (session, engine) = await activeIn(room);

      final rebuilt = buildTestRoom(client);
      joinTheCall(
        rebuilt,
        '@ann:example.org',
        deviceId: 'ANN',
        fociActive: {'sessionId': 'fresh'},
      );
      client.rooms
        ..clear()
        ..add(rebuilt);
      await sync();

      expect(session.phase, CallSessionPhase.active);
      expect(engine.updatedRemotes.length, greaterThan(0));
      expect(session.room, same(rebuilt));
    });

    group('leaving the room ends the call without writing to it', () {
      late List<http.Request> requests;
      late Client recording;
      late Room recordingRoom;

      setUp(() {
        requests = [];
        recording = recordingRequests(requests);
        recordingRoom = buildTestRoom(recording);
        recording.rooms.add(recordingRoom);
      });

      test('a sync that lists the room as left', () async {
        final (session, engine) = await activeIn(recordingRoom);
        requests.clear();

        recording.onSync.add(
          SyncUpdate(
            nextBatch: 'next',
            rooms: RoomsUpdate(leave: {recordingRoom.id: LeftRoomUpdate()}),
          ),
        );
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(engine.leaveCalls, 1);
        expect(requests, isEmpty);
      });

      test(
        'a sync after which the room is gone, as blocking leaves a chat',
        () async {
          final (session, engine) = await activeIn(recordingRoom);
          requests.clear();

          recording.rooms.remove(recordingRoom);
          await sync(recording);

          expect(session.phase, CallSessionPhase.ended);
          expect(engine.leaveCalls, 1);
          expect(requests, isEmpty);
        },
      );

      test(
        'a local sync while the cache is being rebuilt keeps the call',
        () async {
          final (session, _) = await activeIn(recordingRoom);

          recording.rooms.clear();
          recording.onSync.add(SyncUpdate(nextBatch: ''));
          await pumpEventQueue();

          expect(session.phase, CallSessionPhase.active);
        },
      );
    });

    test(
      'signing out elsewhere ends the call at once, without writing',
      () async {
        final requests = <http.Request>[];
        final recording = recordingRequests(requests);
        final (session, engine) = await activeIn(buildTestRoom(recording));
        requests.clear();

        recording.onLoginStateChanged.add(LoginState.loggedOut);
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(engine.leaveCalls, 1);
        expect(requests, isEmpty);
      },
    );

    test('hanging up stops the microphone and camera, and ends the call, '
        'before the membership clear reaches the server', () async {
      final clearing = Completer<void>();
      final slow = loggingMemberPuts(
        [],
        onPut: (body) async {
          if (body.contains('"memberships":[]')) await clearing.future;
          return null;
        },
      );
      final (session, engine) = await activeIn(sendRoom(slow));

      final hungUp = session.hangUp(byUser: true);
      await pumpEventQueue();

      expect(engine.leaveCalls, 1);
      expect(session.phase, CallSessionPhase.ended);
      clearing.complete();
      await hungUp;
    });

    test(
      'a hang-up while our first key is being set leaves nothing listening to '
      'the app',
      () async {
        final engine = _SlowKeyEngine();
        final camera = _ListenedFlag();
        final session = incoming(
          inRoom: sendRoom(),
          engine: engine,
          pictureInPictureCamera: camera,
        );

        final accepted = session.accept();
        await pumpEventQueue();
        final hungUp = session.hangUp(byUser: true);
        await pumpEventQueue();
        engine.keySet.complete();
        await hungUp;
        await accepted.catchError((_) {});
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(camera.listened, isFalse);
      },
    );

    test('a call that is let go ends and releases its engine without '
        'writing anything', () async {
      final requests = <http.Request>[];
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        connections: FakeCallConnections(),
        room: buildTestRoom(recordingRequests(requests)),
        callId: 'call1',
        kind: CallKind.voice,
        engineBuilder: () => engine,
      );
      expect(session.engine, same(engine));
      final phases = <CallSessionPhase>[];
      session.phaseStream.listen(phases.add);

      session.dispose();
      await pumpEventQueue();

      expect(phases, [CallSessionPhase.ended]);
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(requests, isEmpty);
    });
  });

  group('sender keys', () {
    const mod = '@mod:example.org';
    const carolId = VoipParticipantId(userId: _carol, deviceId: 'CAROL');
    const sends = _encryptedFoci;

    ({
      CallSession session,
      ToDeviceRecordingClient client,
      Room room,
      FakeCallEngine engine,
    })
    inCall({Map<String, Map<String, Object?>> others = const {_bob: sends}}) {
      const devices = {_bob: 'BOB', _carol: 'CAROL'};
      final engine = FakeCallEngine();
      final call = keyDeliveryCall(
        inCall: {for (final userId in others.keys) userId: devices[userId]!},
        fociActive: others,
        engine: engine,
        keyDeliveryDelay: Duration.zero,
      );
      setPowerLevels(call.room, {
        'users': {mod: 50},
      });
      return (
        session: call.session,
        client: call.client,
        room: call.room,
        engine: engine,
      );
    }

    List<int?> senderKeyGensTo(ToDeviceRecordingClient c, String deviceId) => [
      for (final send in c.sent)
        if (send.deviceId == deviceId && send.type == callSenderKeyEventType)
          parseSenderKeyContent(
            send.body.cast<String, Object?>(),
            callId: 'call1',
          )?.gen,
    ];

    ToDeviceEvent senderKeyFrom(
      String userId,
      String deviceId,
      SenderKey key,
    ) => keyEvent(sender: userId, curveKey: 'curve-$deviceId', key: key);

    SenderKey keyOf(int gen, {int epoch = 0, int fill = 1}) => (
      epoch: epoch,
      gen: gen,
      key: Uint8List.fromList(List.filled(32, fill)),
    );

    test('our key goes to every device in the call', () async {
      final call = inCall(others: {_bob: sends, _carol: sends});

      await call.session.accept();
      await pumpEventQueue();

      expect(senderKeyGensTo(call.client, 'BOB'), [1]);
      expect(senderKeyGensTo(call.client, 'CAROL'), [1]);
    });

    test('a device the key policy refuses gets no sender key', () async {
      final call = inCall();
      testMasterKey(call.client, _bob);
      setTestDevices(call.client, _bob, {'BOB': null});

      await call.session.accept();
      await pumpEventQueue();

      expect(senderKeyGensTo(call.client, 'BOB'), isEmpty);
    });

    test('a key from a participant is loaded into its slot', () async {
      final call = inCall();
      await call.session.accept();

      call.client.onToDeviceEvent.add(senderKeyFrom(_bob, 'BOB', keyOf(3)));
      await pumpEventQueue();

      expect(call.engine.peerKeys[bob], {2: keyOf(3).key});
    });

    test('a key from a device not yet in the call is held and loaded once it '
        'joins', () async {
      final call = inCall(others: const {});
      setSelfSignedTestDevices(call.client, _bob, ['BOB']);
      await call.session.accept();

      call.client.onToDeviceEvent.add(senderKeyFrom(_bob, 'BOB', keyOf(2)));
      await pumpEventQueue();
      expect(call.engine.peerKeys, isEmpty);

      joinTheCall(call.room, _bob, deviceId: 'BOB', fociActive: sends);
      await sync(call.client);

      expect(call.engine.peerKeys[bob], {1: keyOf(2).key});
    });

    test('an older key arriving after a newer one is ignored', () async {
      final call = inCall();
      await call.session.accept();

      call.client.onToDeviceEvent
        ..add(senderKeyFrom(_bob, 'BOB', keyOf(3, fill: 3)))
        ..add(senderKeyFrom(_bob, 'BOB', keyOf(2, fill: 2)));
      await pumpEventQueue();

      expect(call.engine.peerKeys[bob], {2: keyOf(3, fill: 3).key});
    });

    test('a device that rejoins under a new membership gets our key '
        'again', () async {
      final call = inCall();
      await call.session.accept();
      await pumpEventQueue();

      joinTheCall(
        call.room,
        _bob,
        deviceId: 'BOB',
        fociActive: sends,
        createdAtMs: 99,
      );
      await sync(call.client);

      expect(senderKeyGensTo(call.client, 'BOB'), [1, 1]);
    });

    test('a leave moves us to a new key after the leave and use delays, sent '
        'to whoever stays', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.flushMicrotasks();

        leaveTheCall(call.room, _carol);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 2));

        expect(call.engine.ownKeys.keys, [0, 1]);
        expect(senderKeyGensTo(call.client, 'BOB'), [1, 2]);
        expect(senderKeyGensTo(call.client, 'CAROL'), [1]);
        expect(call.engine.sendSlots, [0]);

        async.elapse(const Duration(seconds: 2));
        expect(call.engine.sendSlots, [0, 1]);
      });
    });

    test('a removal in room state moves us to a new key at once, forgets the '
        'removed device and never takes or sends it a key again', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.flushMicrotasks();
        call.client.onToDeviceEvent.add(
          senderKeyFrom(_carol, 'CAROL', keyOf(1)),
        );
        async.flushMicrotasks();
        expect(call.engine.peerKeys[carolId], isNotNull);

        setCallRemoval(call.room, _carol, by: mod);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.flushMicrotasks();

        expect(call.engine.ownKeys.keys, [0, 1]);
        expect(call.engine.forgotten, [carolId]);
        expect(call.engine.removedRemotes, [carolId]);

        call.client.onToDeviceEvent.add(
          senderKeyFrom(_carol, 'CAROL', keyOf(5)),
        );
        async.elapse(const Duration(seconds: 5));

        expect(senderKeyGensTo(call.client, 'CAROL'), [1]);
        expect(call.engine.peerKeys[carolId], isNull);
        expect(call.engine.sendSlots, [0, 1]);
      });
    });

    test('a device the key policy starts refusing mid-call moves us to a new '
        'key it never gets', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.flushMicrotasks();

        testMasterKey(call.client, _bob);
        setTestDevices(call.client, _bob, {'BOB': null});
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 4));

        expect(call.engine.ownKeys.keys, [0, 1]);
        expect(senderKeyGensTo(call.client, 'BOB'), [1]);
        expect(senderKeyGensTo(call.client, 'CAROL'), [1, 2]);
        expect(call.engine.sendSlots, [0, 1]);
      });
    });

    test('a key sent from another user\'s device is ignored', () async {
      final call = inCall();
      setSelfSignedTestDevices(call.client, _mallory, ['MALDEV']);
      await call.session.accept();

      call.client.onToDeviceEvent.add(
        keyEvent(sender: _bob, curveKey: 'curve-MALDEV', key: keyOf(1)),
      );
      await pumpEventQueue();

      expect(call.engine.peerKeys, isEmpty);
    });

    test('a key for another call is ignored', () async {
      final call = inCall();
      await call.session.accept();

      call.client.onToDeviceEvent.add(
        keyEvent(
          sender: _bob,
          curveKey: 'curve-BOB',
          callId: 'call0',
          key: keyOf(1),
        ),
      );
      await pumpEventQueue();

      expect(call.engine.peerKeys, isEmpty);
    });

    test('a device that rejoins with its clock set back is heard under its new '
        'membership, and a late key from its old one is not', () async {
      final call = inCall();
      joinTheCall(
        call.room,
        _bob,
        deviceId: 'BOB',
        fociActive: sends,
        createdAtMs: 500,
      );
      await call.session.accept();
      call.client.onToDeviceEvent.add(
        senderKeyFrom(_bob, 'BOB', keyOf(1, epoch: 500)),
      );
      await pumpEventQueue();

      joinTheCall(
        call.room,
        _bob,
        deviceId: 'BOB',
        fociActive: sends,
        createdAtMs: 100,
      );
      await sync(call.client);
      call.client.onToDeviceEvent
        ..add(senderKeyFrom(_bob, 'BOB', keyOf(1, epoch: 100, fill: 2)))
        ..add(senderKeyFrom(_bob, 'BOB', keyOf(2, epoch: 500, fill: 3)));
      await pumpEventQueue();

      expect(call.engine.peerKeys[bob], {0: keyOf(1, epoch: 100, fill: 2).key});
    });

    test('a device the key policy refuses before its new Olm session lands '
        'still moves us to a new key', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.flushMicrotasks();

        testMasterKey(call.client, _bob);
        call.client.onToDeviceEvent.add(dummyFrom(_bob, 'BOB'));
        async.flushMicrotasks();
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 4));

        expect(call.engine.ownKeys.keys, [0, 1]);
        expect(senderKeyGensTo(call.client, 'BOB'), [1]);
        expect(senderKeyGensTo(call.client, 'CAROL'), [1, 2]);
      });
    });

    test('a device removed before we join never gets our key or reaches the '
        'engine', () async {
      final call = inCall(others: {_bob: sends, _carol: sends});
      setCallRemoval(call.room, _carol, by: mod);

      await call.session.accept();
      await pumpEventQueue();

      expect(senderKeyGensTo(call.client, 'CAROL'), isEmpty);
      expect(senderKeyGensTo(call.client, 'BOB'), [1]);
      expect(call.engine.updatedRemotes, isNot(contains(carolId)));
    });

    test('someone who leaves the room is gone from the call at once, though '
        'their membership still lists it', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.flushMicrotasks();

        call.room.setState(
          StrippedStateEvent(
            type: EventTypes.RoomMember,
            senderId: _carol,
            stateKey: _carol,
            content: const {'membership': 'leave'},
          ),
        );
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 4));

        expect(call.engine.removedRemotes, [carolId]);
        expect(senderKeyGensTo(call.client, 'CAROL'), [1]);
        expect(senderKeyGensTo(call.client, 'BOB'), [1, 2]);
      });
    });

    test('a device that restarts has its old keys dropped, so its media waits '
        'for its new key', () async {
      final call = inCall();
      await call.session.accept();
      call.client.onToDeviceEvent.add(senderKeyFrom(_bob, 'BOB', keyOf(1)));
      await pumpEventQueue();
      expect(call.engine.peerKeys[bob], {0: keyOf(1).key});

      joinTheCall(
        call.room,
        _bob,
        deviceId: 'BOB',
        fociActive: sends,
        createdAtMs: 99,
      );
      await sync(call.client);

      expect(call.engine.forgotten, [bob]);
      expect(call.engine.peerKeys[bob], isNull);

      final fresh = keyOf(1, epoch: 99, fill: 2);
      call.client.onToDeviceEvent.add(senderKeyFrom(_bob, 'BOB', fresh));
      await pumpEventQueue();
      expect(call.engine.peerKeys[bob], {0: fresh.key});
    });

    test('a removal drops the keys of a device that had already left', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.flushMicrotasks();
        call.client.onToDeviceEvent.add(
          senderKeyFrom(_carol, 'CAROL', keyOf(1)),
        );
        async.flushMicrotasks();
        leaveTheCall(call.room, _carol);
        call.client.onSync.add(SyncUpdate(nextBatch: 'left'));
        async.elapse(const Duration(seconds: 5));
        expect(call.engine.forgotten, isEmpty);

        setCallRemoval(call.room, _carol, by: mod);
        call.client.onSync.add(SyncUpdate(nextBatch: 'removed'));
        async.flushMicrotasks();

        expect(call.engine.forgotten, [carolId]);
      });
    });

    void joinsLater(
      ({
        CallSession session,
        ToDeviceRecordingClient client,
        Room room,
        FakeCallEngine engine,
      })
      call,
    ) {
      setSelfSignedTestDevices(call.client, _caller, ['CALLERDEV']);
      joinTheCall(call.room, _caller, deviceId: 'CALLERDEV', fociActive: sends);
    }

    test('a device that joins while our key is under 10 s old gets that '
        'key', () {
      fakeAsync((async) {
        final call = inCall();
        unawaited(call.session.accept());
        async.elapse(const Duration(seconds: 9));

        joinsLater(call);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 5));

        expect(senderKeyGensTo(call.client, 'CALLERDEV'), [1]);
        expect(call.engine.ownKeys.keys, [0]);
      });
    });

    test('in a call we sat in alone for a while, the first device to join '
        'gets the key nobody has received yet, with no new key', () {
      fakeAsync((async) {
        final call = inCall(others: const {});
        unawaited(call.session.accept());
        async.elapse(const Duration(seconds: 12));

        joinsLater(call);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 5));

        expect(senderKeyGensTo(call.client, 'CALLERDEV'), [1]);
        expect(call.engine.ownKeys.keys, [0]);
      });
    });

    test('a device that joins once our key is 10 s old gets only a new key, '
        'which everyone gets and we use after the use delay', () {
      fakeAsync((async) {
        final call = inCall();
        unawaited(call.session.accept());
        async.elapse(const Duration(seconds: 10));

        joinsLater(call);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.flushMicrotasks();

        expect(senderKeyGensTo(call.client, 'CALLERDEV'), [2]);
        expect(senderKeyGensTo(call.client, 'BOB'), [1, 2]);
        expect(call.engine.sendSlots, [0]);

        async.elapse(const Duration(seconds: 2));
        expect(call.engine.sendSlots, [0, 1]);
      });
    });

    test('a leave and a join in one sync never hand the leaver the new '
        'key', () {
      fakeAsync((async) {
        final call = inCall(others: {_bob: sends, _carol: sends});
        unawaited(call.session.accept());
        async.elapse(const Duration(seconds: 10));

        leaveTheCall(call.room, _carol);
        joinsLater(call);
        call.client.onSync.add(SyncUpdate(nextBatch: 'next'));
        async.elapse(const Duration(seconds: 5));

        expect(senderKeyGensTo(call.client, 'CAROL'), [1]);
        expect(senderKeyGensTo(call.client, 'CALLERDEV'), [2]);
        expect(senderKeyGensTo(call.client, 'BOB'), [1, 2]);
      });
    });

    test('our key is replaced every 90 minutes', () {
      fakeAsync((async) {
        final call = inCall();
        joinTheCall(
          call.room,
          _bob,
          deviceId: 'BOB',
          fociActive: sends,
          expiresIn: const Duration(hours: 4),
        );
        unawaited(call.session.accept());
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 90));
        expect(senderKeyGensTo(call.client, 'BOB'), [1, 2]);

        async.elapse(const Duration(minutes: 90));
        expect(senderKeyGensTo(call.client, 'BOB'), [1, 2, 3]);
        expect(call.session.phase, CallSessionPhase.active);
      });
    });
  });

  group('moderation', () {
    const mod = '@mod:example.org';

    Event removal(
      Room r, {
      String sender = mod,
      required String userId,
      String callId = 'call1',
    }) => buildTestEvent(
      r,
      eventId: '\$remove-$userId-$callId',
      senderId: sender,
      type: callRemoveEventType,
      content: {'call_id': callId, 'user_id': userId},
    );

    Event mute(
      Room r, {
      String sender = mod,
      String userId = _me,
      required int joinedAt,
    }) => buildTestEvent(
      r,
      eventId: '\$mute-$userId-$joinedAt',
      senderId: sender,
      type: callMuteEventType,
      content: {
        'call_id': 'call1',
        'user_id': userId,
        'membership_created_ts': joinedAt,
      },
    );

    ({
      CallSession session,
      FakeCallEngine engine,
      SendRecordingRoom room,
      List<String> puts,
    })
    joined() {
      final puts = <String>[];
      final r = sendRoom(loggingMemberPuts(puts));
      setPowerLevels(r, {
        'users': {mod: 50},
      });
      final engine = FakeCallEngine();
      final session = incoming(inRoom: r, engine: engine);
      return (session: session, engine: engine, room: r, puts: puts);
    }

    void deliver(Event event) => event.room.client.onTimelineEvent.add(event);

    test('someone who outranks us removing us ends the call as removed by '
        'them, clears our membership and posts nothing', () async {
      final call = joined();
      joinTheCall(call.room, mod, deviceId: 'MOD');
      await call.session.accept();

      deliver(removal(call.room, userId: _me));
      await untilPhase(call.session, CallSessionPhase.ended);
      await call.session.hangUpFinished;

      expect(call.session.endReason, CallEndReason.removed);
      expect(call.session.removedBy, mod);
      expect(call.session.failure, isNull);
      expect(jsonDecode(call.puts.last), {
        'memberships': <Object?>[],
        'left_call_id': 'call1',
      });
      expect(call.room.attempts, isEmpty);
    });

    for (final (reason, sender, callId) in [
      ('someone who does not outrank us', _bob, 'call1'),
      ('another call', mod, 'another-call'),
    ]) {
      test('a removal from $reason is ignored', () async {
        final call = joined();
        await call.session.accept();

        deliver(
          removal(call.room, sender: sender, userId: _me, callId: callId),
        );
        await pumpEventQueue();

        expect(call.session.phase, CallSessionPhase.active);
      });
    }

    test('a callee removed while it still rings declines nothing', () async {
      final call = joined();

      deliver(removal(call.room, userId: _me));
      await untilPhase(call.session, CallSessionPhase.ended);
      await call.session.hangUpFinished;

      expect(call.session.endReason, CallEndReason.removed);
      expect(call.room.attempts, isEmpty);
    });

    test('someone else\'s removal seen in the timeline drops them from our '
        'call at once and moves us to a new key', () async {
      final call = joined();
      joinTheCall(call.room, _bob, deviceId: 'BOB');
      await call.session.accept();

      deliver(removal(call.room, userId: _bob));
      await pumpEventQueue();

      expect(call.engine.removedRemotes, [bob]);
      expect(call.engine.ownKeys.keys, [0, 1]);
      expect(call.session.phase, CallSessionPhase.active);
    });

    test(
      'a removal heard before we join changes nothing until we do',
      () async {
        final call = joined();
        joinTheCall(call.room, _bob, deviceId: 'BOB');
        call.session.engine;

        deliver(removal(call.room, userId: _carol));
        await pumpEventQueue();

        expect(call.session.everHadRemote, isFalse);
        expect(call.engine.updatedRemotes, isEmpty);
      },
    );

    test('a removal heard before we join keeps them out once we do', () async {
      final call = joined();
      joinTheCall(call.room, _bob, deviceId: 'BOB');
      call.session.engine;
      deliver(removal(call.room, userId: _bob));
      await pumpEventQueue();

      await call.session.accept();
      await pumpEventQueue();

      expect(call.engine.updatedRemotes, isNot(contains(bob)));
      expect(call.session.everHadRemote, isFalse);
    });

    test(
      'a removal from someone who does not outrank them is ignored',
      () async {
        final call = joined();
        joinTheCall(call.room, _bob, deviceId: 'BOB');
        await call.session.accept();

        deliver(removal(call.room, sender: _carol, userId: _bob));
        await pumpEventQueue();

        expect(call.engine.removedRemotes, isEmpty);
        expect(call.engine.forgotten, isEmpty);
      },
    );

    test('a removal of us in room state ends the call naming the '
        'moderator', () async {
      final call = joined();
      joinTheCall(call.room, _bob, deviceId: 'BOB');
      await call.session.accept();

      setCallRemoval(call.room, _me, by: mod);
      await sync(call.room.client);

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.session.endReason, CallEndReason.removed);
      expect(call.session.removedBy, mod);
    });

    test('joining a call that already names us as removed never shows it '
        'active', () async {
      final call = joined();
      joinTheCall(call.room, _bob, deviceId: 'BOB');
      setCallRemoval(call.room, _me, by: mod);
      final phases = <CallSessionPhase>[];
      call.session.phaseStream.listen(phases.add);

      await call.session.accept();
      await pumpEventQueue();

      expect(phases, isNot(contains(CallSessionPhase.active)));
      expect(call.session.endReason, CallEndReason.removed);
      expect(call.session.removedBy, mod);
    });

    test('a removal the engine heard while joining ends the call as '
        'removed', () async {
      final r = sendRoom();
      final engine = _RemovedWhileJoiningEngine();
      final session = incoming(inRoom: r, engine: engine);

      await session.accept();
      await untilPhase(session, CallSessionPhase.ended);

      expect(session.endReason, CallEndReason.removed);
    });

    test('a mute in a direct chat is ignored, whatever the roles', () async {
      final call = joined();
      call.room.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          mod: [call.room.id],
        },
      );
      await call.session.accept();

      deliver(mute(call.room, joinedAt: _publishedJoinTime(call.puts.first)));
      await pumpEventQueue();

      expect(call.engine.microphoneMutedRequests, isEmpty);
    });

    test(
      'the server cutting us off ends the call as removed, naming nobody',
      () async {
        final call = joined();
        await call.session.accept();

        call.engine.setStatus(CallEngineStatus.removed);
        await untilPhase(call.session, CallSessionPhase.ended);

        expect(call.session.endReason, CallEndReason.removed);
        expect(call.session.removedBy, isNull);
        expect(call.session.failure, isNull);
      },
    );

    test('joining a call we were removed from ends as removed, reported '
        'nowhere', () async {
      final logs = recordDebugPrints();
      final r = sendRoom();
      final session = incoming(
        inRoom: r,
        engine: FakeCallEngine(
          failJoin: true,
          joinError: const CallRemovedException(),
        ),
      );

      await expectLater(session.accept(), throwsA(isA<CallRemovedException>()));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.removed);
      expect(session.failure, isNull);
      expect(r.attempts, isEmpty);
      expect(reported(logs), isEmpty);
    });

    test('a mute aimed at our join mutes the microphone, republishes and '
        'names who did it until we unmute', () async {
      final call = joined();
      await call.session.accept();
      final published = call.puts.length;

      deliver(mute(call.room, joinedAt: _publishedJoinTime(call.puts.first)));
      await pumpEventQueue();

      expect(call.engine.microphoneMutedRequests, [true]);
      expect(call.session.mutedBy, mod);
      expect(call.puts.length, greaterThan(published));

      await call.session.setMicrophoneMuted(false);

      expect(call.session.mutedBy, isNull);
    });

    for (final (reason, build)
        in <(String, Event Function(SendRecordingRoom, int))>[
          (
            'an earlier join of ours',
            (r, joinedAt) => mute(r, joinedAt: joinedAt - 1),
          ),
          (
            'someone who does not outrank us',
            (r, joinedAt) => mute(r, sender: _bob, joinedAt: joinedAt),
          ),
          (
            'someone else',
            (r, joinedAt) => mute(r, userId: _bob, joinedAt: joinedAt),
          ),
        ]) {
      test('a mute aimed at $reason changes nothing', () async {
        final call = joined();
        await call.session.accept();

        deliver(build(call.room, _publishedJoinTime(call.puts.first)));
        await pumpEventQueue();

        expect(call.engine.microphoneMutedRequests, isEmpty);
        expect(call.session.mutedBy, isNull);
      });
    }

    test('a mute while we are already muted names nobody', () async {
      final call = joined();
      await call.session.accept();
      call.engine.setParticipants([localParticipant(muted: true)]);

      deliver(mute(call.room, joinedAt: _publishedJoinTime(call.puts.first)));
      await pumpEventQueue();

      expect(call.engine.microphoneMutedRequests, isEmpty);
      expect(call.session.mutedBy, isNull);
    });

    test('muting someone asks for this call', () async {
      final call = joined();
      joinTheCall(call.room, _bob, deviceId: 'BOB');
      await call.session.accept();

      await call.session.mute(_bob);

      expect(call.room.requests.single.type, callMuteEventType);
      expect(call.room.requests.single.content['call_id'], 'call1');
    });
  });
}

class _JournalEngine extends FakeCallEngine {
  _JournalEngine({super.kind, super.joinGate});

  final journal = <String>[];

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    journal.add('camera $enabled');
    await super.setCameraEnabled(enabled);
  }

  @override
  Future<void> startLocalMedia() async {
    journal.add('local media');
    await super.startLocalMedia();
  }

  @override
  Future<void> setOwnKey(int slot, Uint8List key) async {
    journal.add('key $slot');
    await super.setOwnKey(slot, key);
  }

  @override
  Future<void> sendWithSlot(int slot) async {
    journal.add('send $slot');
    await super.sendWithSlot(slot);
  }

  @override
  Future<void> join() async {
    journal.add('join');
    await super.join();
  }
}

class _SlowKeyEngine extends FakeCallEngine {
  final keySet = Completer<void>();

  @override
  Future<void> setOwnKey(int slot, Uint8List key) => keySet.future;
}

class _ListenedFlag extends ValueNotifier<bool> {
  _ListenedFlag() : super(false);

  bool get listened => hasListeners;
}

class _RemovedWhileJoiningEngine extends FakeCallEngine {
  @override
  Future<void> join() async {
    await super.join();
    setStatus(CallEngineStatus.removed);
  }
}

class _OpeningSessionEngine extends FakeCallEngine {
  _OpeningSessionEngine({super.joinGate, super.failJoin});

  bool _sessionOpen = false;

  void openSession() {
    _sessionOpen = true;
    localStateController.add(null);
  }

  @override
  Map<String, Object?>? get localFociInfo => joined
      ? super.localFociInfo
      : _sessionOpen
      ? {'sessionId': 'opening-session', 'tracks': const <String, Object?>{}}
      : null;
}
