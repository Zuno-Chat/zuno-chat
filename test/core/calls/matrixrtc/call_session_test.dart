import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:permission_handler/permission_handler.dart';
import 'package:zuno/core/calls/call_engine.dart';
import 'package:zuno/core/calls/matrixrtc/call_encryption_key_event.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/app_lifecycle.dart';
import '../../../helpers/call_membership.dart';
import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_call_engine.dart';
import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_permissions.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/send_recording_room.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _caller = '@caller:example.org';
const _mallory = '@mallory:example.org';

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
    httpClient: MockClient(handler),
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

  CallSession incoming({
    Room? inRoom,
    String callId = 'call1',
    CallKind kind = CallKind.voice,
    CallEngine? engine,
    Uint8List? key,
    Duration? keyRelayDelay,
    ValueListenable<bool>? pictureInPictureCamera,
  }) {
    final built = engine ?? FakeCallEngine();
    final session = CallSession.forIncoming(
      room: inRoom ?? room,
      callId: callId,
      kind: kind,
      engineBuilder: () => built,
      initialEncryptionKeyForTesting: key,
      keyRelayBaseDelay: keyRelayDelay,
      keyRelayMaxDelay: keyRelayDelay,
      pictureInPictureCamera: pictureInPictureCamera,
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
    int createdAtMs = 0,
  }) => r.setState(
    callMemberEvent(
      r,
      userId: userId,
      deviceId: deviceId,
      callId: callId,
      fociActive: fociActive,
      createdAtMs: createdAtMs,
      expiresIn: const Duration(minutes: 5),
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
    String type = callEncryptionKeyEventType,
    String callId = 'call1',
    Uint8List? key,
  }) => ToDeviceEvent(
    sender: sender,
    type: type,
    content: buildCallEncryptionKeyContent(
      callId: callId,
      key: key ?? testKey(),
    ),
    encryptedContent: {'sender_key': curveKey, 'algorithm': 'm.olm.v1'},
  );

  test(
    'a call whose engine accepts the key and joins reaches active',
    () async {
      final engine = FakeCallEngine();
      final session = incoming(engine: engine, key: testKey());
      final phases = <CallSessionPhase>[];
      session.phaseStream.listen(phases.add);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(session.endReason, isNull);
      expect(session.failedMessage, isNull);
      expect(engine.joined, isTrue);
      expect(engine.appliedKey, testKey());
      expect(phases, [CallSessionPhase.connecting, CallSessionPhase.active]);
    },
  );

  group('sad paths', () {
    test('a call whose encryption mechanism cannot encrypt the packets fails '
        'with an error', () async {
      final engine = FakeCallEngine(failSetEncryptionKey: true);
      final session = incoming(engine: engine, key: testKey());
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
        final session = incoming(
          engine: FakeCallEngine(failSetEncryptionKey: true),
        );
        await session.accept();
        expect(session.phase, CallSessionPhase.active);

        client.onToDeviceEvent.add(keyEvent());
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failedMessage, callDidNotConnectMessage);
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

        expect(session.failedMessage, isNull);
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
      expect(session.failedMessage, callDidNotConnectMessage);
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(r.attempts, isEmpty);
    });

    test('a room-permission failure surfaces a specific message', () async {
      final session = incoming(
        engine: FakeCallEngine(
          failJoin: true,
          joinError: MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error':
                "You don't have permission to post that to the room. "
                'user_level (0) < send_level (50)',
          }),
        ),
      );

      await expectLater(session.accept(), throwsA(isA<MatrixException>()));

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(
        session.failedMessage,
        'You do not have permission to start calls in this room',
      );
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

      test('a microphone refused at the prompt is not reported', () async {
        permissions.onRequest = permissionDenied;
        final logs = recordDebugPrints();
        final session = incoming();

        await expectLater(
          session.accept(),
          throwsA(isA<MicrophoneUnavailable>()),
        );

        expect(session.failedMessage, microphoneUnavailableMessage);
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
        expect(session.failedMessage, 'Connection lost');
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
      expect(session.failedMessage, 'Connection lost');

      final callsBeforeSeed = engine.updateRemoteParticipantCalls;
      joinTheCall(raceRoom, _bob);
      await sync(raceClient);

      expect(engine.updateRemoteParticipantCalls, callsBeforeSeed);
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
        expect(session.failedMessage, microphoneUnavailableMessage);
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
        Object? failure;
        unawaited(
          session.accept().catchError((Object e) {
            failure = e;
          }),
        );

        async.flushMicrotasks();

        expect(failure, isException);
        expect(session.phase, CallSessionPhase.ended);
        expect(session.failedMessage, microphoneUnavailableMessage);
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
      expect(session.failedMessage, microphoneUnavailableMessage);
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
      expect(session.failedMessage, microphoneUnavailableMessage);
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
      key: testKey(),
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

  test('an outgoing call makes a 32-byte key, and two calls never make the '
      'same one', () async {
    final engineA = FakeCallEngine();
    final sessionA = outgoing(sendRoom(), engine: engineA);
    await untilPhase(sessionA, CallSessionPhase.active);

    final engineB = FakeCallEngine();
    final sessionB = outgoing(sendRoom(), engine: engineB);
    await untilPhase(sessionB, CallSessionPhase.active);

    expect(engineA.appliedKey, hasLength(32));
    expect(engineB.appliedKey, hasLength(32));
    expect(engineA.appliedKey, isNot(engineB.appliedKey));
  });

  group('callee applying a key that arrives over real to-device', () {
    void callerInCall() {
      setSelfSignedTestDevices(client, _caller, ['CALLERDEV']);
      joinTheCall(room, _caller, deviceId: 'CALLERDEV');
    }

    test('a key that arrives once the call is active is applied, and the '
        'membership is republished as encrypted', () async {
      final published = <String>[];
      final logging = loggingMemberPuts(published);
      final r = buildTestRoom(logging);
      setSelfSignedTestDevices(logging, _caller, ['CALLERDEV']);
      joinTheCall(r, _caller, deviceId: 'CALLERDEV');
      final engine = FakeCallEngine();
      final session = incoming(inRoom: r, engine: engine);
      await session.accept();
      final before = published.length;
      expect(engine.appliedKey, isNull);
      expect(published.last, contains('"encrypted":false'));

      logging.onToDeviceEvent.add(keyEvent());
      await pumpEventQueue();

      expect(engine.appliedKey, testKey());
      expect(session.isEncrypted, isTrue);
      expect(published, hasLength(before + 1));
      expect(published.last, contains('"encrypted":true'));
    });

    test('a key from a device that is not in the call is rejected', () async {
      setSelfSignedTestDevices(client, _mallory, ['MALDEV']);
      final engine = FakeCallEngine();
      await incoming(engine: engine).accept();

      client.onToDeviceEvent.add(
        keyEvent(sender: _mallory, curveKey: 'curve-MALDEV'),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, isNull);
    });

    test(
      'a key whose sender_key belongs to a different user is rejected',
      () async {
        callerInCall();
        setSelfSignedTestDevices(client, _mallory, ['MALDEV']);
        final engine = FakeCallEngine();
        final session = incoming(engine: engine);
        await session.accept();

        client.onToDeviceEvent.add(keyEvent(curveKey: 'curve-MALDEV'));
        await pumpEventQueue();

        expect(engine.appliedKey, isNull);
        expect(session.isEncrypted, isFalse);
      },
    );

    test(
      'a key arriving before the sender\'s membership is applied once it lands',
      () async {
        setSelfSignedTestDevices(client, _caller, ['CALLERDEV']);
        final engine = FakeCallEngine();
        final session = incoming(engine: engine);
        await session.accept();

        client.onToDeviceEvent.add(keyEvent());
        await pumpEventQueue();
        expect(engine.appliedKey, isNull);

        joinTheCall(room, _caller, deviceId: 'CALLERDEV');
        await sync();

        expect(engine.appliedKey, testKey());
        expect(session.isEncrypted, isTrue);
      },
    );

    test('a to-device event that is not this call\'s key is ignored', () async {
      callerInCall();
      final engine = FakeCallEngine();
      final session = incoming(engine: engine);
      await session.accept();

      client.onToDeviceEvent
        ..add(keyEvent(type: 'm.some.other.event'))
        ..add(keyEvent(callId: 'some-other-call'));
      await pumpEventQueue();

      expect(engine.appliedKey, isNull);
      expect(session.phase, CallSessionPhase.active);
    });

    test('a second key for the call is ignored — exactly one key per '
        'call', () async {
      callerInCall();
      final engine = FakeCallEngine();
      await incoming(engine: engine).accept();

      client.onToDeviceEvent
        ..add(keyEvent())
        ..add(
          keyEvent(
            key: Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)),
          ),
        );
      await pumpEventQueue();

      expect(engine.appliedKey, testKey());
    });
  });

  group('caller relaying the key to newly-discovered devices', () {
    late List<String> keyQueries;
    late bool failNextQuery;
    late Client relayClient;
    late Room relayRoom;

    setUp(() {
      keyQueries = [];
      failNextQuery = false;
      relayClient = buildCallTestClient((request) async {
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
      relayRoom = buildTestRoom(relayClient);
    });

    CallSession relaying({bool holdsKey = true}) => incoming(
      inRoom: relayRoom,
      key: holdsKey ? testKey() : null,
      keyRelayDelay: Duration.zero,
    );

    void bobInCall([Map<String, Object?> fociActive = const {}]) => joinTheCall(
      relayRoom,
      _bob,
      deviceId: 'BOBDEVICE',
      fociActive: fociActive,
    );

    test('a session with no key yet asks for no device keys at all', () async {
      bobInCall();
      final session = relaying(holdsKey: false);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(keyQueries, isEmpty);
    });

    test('a session that already holds a key asks for the device keys of a '
        'device the moment it is discovered', () async {
      bobInCall();
      final session = relaying();

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(keyQueries.first, contains(_bob));
    });

    test(
      'a failed device-key fetch is retried before the relay gives up',
      () async {
        failNextQuery = true;
        bobInCall();

        await relaying().accept();
        await pumpEventQueue();

        expect(keyQueries.length, greaterThanOrEqualTo(2));
      },
    );

    test(
      'a known device that re-joins with a new sessionId is sent the key again',
      () async {
        bobInCall({'sessionId': 'bob-session-1'});
        await relaying().accept();
        await pumpEventQueue();
        final firstPass = keyQueries.length;
        expect(firstPass, greaterThan(0));

        bobInCall({'sessionId': 'bob-session-2'});
        await sync(relayClient);

        expect(keyQueries.length, greaterThan(firstPass));
      },
    );

    test('a relay that gives up while the call is on is reported, without '
        'the device it was for', () async {
      final logs = recordDebugPrints();
      bobInCall();

      await relaying().accept();
      await pumpEventQueue();

      expect(
        reported(logs),
        contains(startsWith('zuno/caught: relay the call key:')),
      );
      final retries = logs.where((l) => l.startsWith('zuno/retry:'));
      expect(retries, isNotEmpty);
      expect(retries, everyElement(startsWith('zuno/retry: call key relay ')));
      expect(logs.join('\n'), isNot(contains('BOBDEVICE')));
    });

    test('a relay cut short by the call ending is not reported', () async {
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
      joinTheCall(endingRoom, _bob, deviceId: 'BOBDEVICE');
      final session = incoming(
        inRoom: endingRoom,
        key: testKey(),
        keyRelayDelay: Duration.zero,
      );

      await session.accept();
      await queried.future;
      await session.hangUp();
      answer.complete();
      await pumpEventQueue();

      expect(
        reported(logs).where((l) => l.contains('relay the call key')),
        isEmpty,
      );
    });

    test('a known device republishing the same sessionId is not sent the key '
        'again', () async {
      bobInCall({'sessionId': 'bob-session-1', 'audioMuted': false});
      await relaying().accept();
      await pumpEventQueue();
      final firstPass = keyQueries.length;
      expect(firstPass, greaterThan(0));

      bobInCall({'sessionId': 'bob-session-1', 'audioMuted': true});
      await sync(relayClient);

      expect(keyQueries, hasLength(firstPass));
    });
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
      expect(session.failedMessage, microphoneUnavailableMessage);
      expect(engine.startLocalMediaCalls, 0);
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

      expect(
        session.failedMessage,
        'You do not have permission to start calls in this room',
      );
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

      expect(
        session.failedMessage,
        'You do not have permission to start calls in this room',
      );
      expect(reported(logs), isEmpty);
    });

    test('an invite that fails for another reason is reported', () async {
      final logs = recordDebugPrints();
      final session = outgoing(sendRoom()..sendError = StateError('boom'));

      await untilPhase(session, CallSessionPhase.ended);

      expect(session.failedMessage, callDidNotConnectMessage);
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
      expect(session.failedMessage, callDidNotConnectMessage);
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
      expect(session.failedMessage, callDidNotConnectMessage);
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
      expect(session.failedMessage, isNull);
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
    test('a key held before joining is applied before join() is ever '
        'called', () async {
      final engine = _JournalEngine();

      await incoming(engine: engine, key: testKey()).accept();

      expect(engine.journal, ['local media', 'key', 'join']);
    });

    test('a callee with no key yet joins without ever calling '
        'setEncryptionKey first', () async {
      final engine = _JournalEngine();

      await incoming(engine: engine).accept();

      expect(engine.journal, ['local media', 'join']);
    });
  });

  group('publishing our membership', () {
    _CountingSession startCountingSessionIn(FakeAsync async) {
      final c = _PublishCountingClient();
      final engine = FakeCallEngine();
      final session = incoming(inRoom: buildTestRoom(c), engine: engine);
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

        r.client.refusal = MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'not a member',
        });
        async.elapse(const Duration(minutes: 1));

        expect(r.publishes, hasLength(2));
        expect(r.session.phase, CallSessionPhase.active);
      });
    });
  });

  group('our membership goes public only once the call hears its key', () {
    test('a refresh while connecting publishes nothing, and joining publishes '
        'once, with the latest state', () {
      fakeAsync((async) {
        final c = _PublishCountingClient();
        final joinGate = Completer<void>();
        final engine = _EarlySessionEngine(joinGate: joinGate);
        final session = incoming(inRoom: buildTestRoom(c), engine: engine);
        unawaited(session.accept());
        async.flushMicrotasks();

        engine.micMuted = true;
        unawaited(session.refreshMembership());
        async.elapse(const Duration(seconds: 2));
        expect(c.publishes, isEmpty);

        joinGate.complete();
        async.elapse(const Duration(seconds: 2));

        expect(session.phase, CallSessionPhase.active);
        expect(c.publishes.single, contains('"audioMuted":true'));
      });
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

    for (final (stage, heldBy, engineSaw) in [
      (
        'the microphone is still opening',
        (Completer<void> gate) => _JournalEngine()..startGate = gate,
        ['local media'],
      ),
      (
        'the engine is still joining',
        (Completer<void> gate) => _JournalEngine(joinGate: gate),
        ['local media', 'join'],
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
        expect(engine.journal, engineSaw);
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
  });

  group('call capacity', () {
    const callFull = 'This call is full. Up to 6 people can join a call.';

    void fill(Room r, int count) {
      for (var i = 1; i <= count; i++) {
        joinTheCall(r, '@p$i:example.org', createdAtMs: i);
      }
    }

    test('accepting a call that already has 6 people ends it as full '
        'without building an engine', () async {
      fill(room, 6);
      var engineBuilds = 0;
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call1',
        kind: CallKind.voice,
        engineBuilder: () {
          engineBuilds++;
          return FakeCallEngine();
        },
      );
      addTearDown(session.dispose);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failedMessage, callFull);
      expect(engineBuilds, 0);
    });

    test('a full call whose engine the call screen already built releases '
        'it', () async {
      fill(room, 6);
      final engine = FakeCallEngine();
      final session = incoming(engine: engine);
      expect(session.engine, same(engine));

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
    });

    test('an engine asked for after the call has ended is released at '
        'once', () async {
      fill(room, 6);
      final engine = FakeCallEngine();
      final session = incoming(engine: engine);
      await session.accept();

      expect(session.engine, same(engine));
      await pumpEventQueue();

      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
    });

    test(
      'a joiner who turns out to be 7th leaves without posting a summary',
      () async {
        final r = sendRoom();
        fill(r, 5);
        final engine = FakeCallEngine();
        final session = incoming(inRoom: r, engine: engine);
        await session.accept();
        await pumpEventQueue();
        expect(session.phase, CallSessionPhase.active);

        joinTheCall(r, '@p6:example.org', createdAtMs: 6);
        joinTheCall(r, _me, createdAtMs: 7);
        await sync();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failedMessage, callFull);
        expect(engine.leaveCalls, 1);
        expect(r.sentEvents, isEmpty);
      },
    );

    test(
      'the published membership keeps one join time across republishes',
      () async {
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

        int joinedAt(String body) {
          final memberships = (jsonDecode(body) as Map)['memberships'] as List;
          return memberships.single['created_ts'] as int;
        }

        expect(publishes, hasLength(2));
        expect(joinedAt(publishes.first), greaterThan(0));
        expect(joinedAt(publishes.last), joinedAt(publishes.first));
      },
    );
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
      'token', () async {
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
          default:
            return null;
        }
      },
    );
    final requests = <http.Request>[];
    final module = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '$base/turn/credentials') {
        return http.Response(jsonEncode({'iceServers': []}), 200);
      }
      return http.Response(jsonEncode({'sessionId': 's1'}), 200);
    });
    client.homeserver = Uri.parse('https://example.org');
    final session = CallSession.forIncoming(
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
  });

  group('the call follows its room and the sign-in', () {
    Future<(CallSession, FakeCallEngine)> activeIn(Room callRoom) async {
      final engine = FakeCallEngine();
      final session = incoming(
        inRoom: callRoom,
        engine: engine,
        key: testKey(),
      );
      await session.accept();
      await pumpEventQueue();
      expect(session.phase, CallSessionPhase.active);
      return (session, engine);
    }

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
      expect(engine.updateRemoteParticipantCalls, greaterThan(0));
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
      'a hang-up while the call key is being set leaves nothing listening to '
      'the app',
      () async {
        final engine = _SlowKeyEngine();
        final camera = _ListenedFlag();
        final session = incoming(
          inRoom: sendRoom(),
          engine: engine,
          key: testKey(),
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
  Future<void> setEncryptionKey(Uint8List key) async {
    journal.add('key');
    await super.setEncryptionKey(key);
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
  Future<void> setEncryptionKey(Uint8List key) => keySet.future;
}

class _ListenedFlag extends ValueNotifier<bool> {
  _ListenedFlag() : super(false);

  bool get listened => hasListeners;
}

class _EarlySessionEngine extends FakeCallEngine {
  _EarlySessionEngine({super.joinGate});

  @override
  Map<String, Object?>? get localFociInfo => {
    'sessionId': 'early-session',
    'tracks': const {'audio': 'audio'},
    'audioMuted': micMuted,
    'encrypted': appliedKey != null,
  };
}
