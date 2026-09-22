import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/call_engine.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/call_encryption_key_event.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

import '../../../helpers/fake_matrix.dart';

class _TestDeviceKeys extends DeviceKeys {
  _TestDeviceKeys(super.json, super.client) : super.fromJson();

  @override
  bool get blocked => false;
}

class _FakeSendEventRoom extends Room {
  _FakeSendEventRoom({required super.client, required super.id});

  final sentEvents = <Map<String, dynamic>>[];

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sentEvents.add(content);
    return client.generateUniqueTransactionId();
  }
}

Client buildCallTestClient(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = buildTestClient(
    userId: '@me:example.org',
    deviceId: 'TESTDEVICE',
    httpClient: MockClient(handler),
  );
  client.baseUri = Uri.parse('https://example.org');
  client.bearerToken = 'test-token';
  return client;
}

class FakeCallEngine implements CallEngine {
  FakeCallEngine({
    this.failSetEncryptionKey = false,
    this.failJoin = false,
    this.joinError,
    this.joinGate,
  });

  final bool failSetEncryptionKey;
  final bool failJoin;
  final Completer<void>? joinGate;

  final Object? joinError;

  bool joined = false;
  Uint8List? appliedKey;

  @override
  CallEngineStatus get status => CallEngineStatus.connected;

  final statusController = StreamController<CallEngineStatus>.broadcast();

  @override
  Stream<CallEngineStatus> get statusStream => statusController.stream;

  @override
  List<CallEngineParticipant> get participants => const [];
  @override
  Stream<List<CallEngineParticipant>> get participantsStream =>
      const Stream.empty();

  @override
  CallKind get kind => CallKind.voice;

  @override
  Future<void> join() async {
    await joinGate?.future;
    if (failJoin) {
      throw joinError ?? StateError('engine failed to connect to the SFU');
    }
    joined = true;
  }

  int leaveCalls = 0;
  int disposeCalls = 0;

  Completer<void>? leaveGate;

  @override
  Future<void> leave() async {
    if (disposeCalls > 0) {
      throw StateError('Cannot add new events after calling close');
    }
    leaveCalls++;
    await leaveGate?.future;
    joined = false;
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> switchToVideo() async {}

  bool micMuted = false;

  final localStateController = StreamController<void>.broadcast();

  @override
  Stream<void> get localStateChangedStream => localStateController.stream;

  @override
  Map<String, Object?>? get localFociInfo => joined
      ? {
          'sessionId': 'fake-session',
          'tracks': const {'audio': 'audio'},
          'audioMuted': micMuted,
          'encrypted': appliedKey != null,
        }
      : null;

  int updateRemoteParticipantCalls = 0;

  @override
  void updateRemoteParticipant(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
  ) {
    updateRemoteParticipantCalls++;
  }

  @override
  void removeRemoteParticipant(VoipParticipantId id) {}

  @override
  Future<void> setEncryptionKey(Uint8List key) async {
    if (failSetEncryptionKey) {
      throw StateError(
        'frame cryptor rejected the key — unable to encrypt packets',
      );
    }
    appliedKey = key;
    localStateController.add(null);
  }

  @override
  CallQuality get quality => CallQuality.good;

  @override
  void dispose() {
    disposeCalls++;
    localStateController.close();
    statusController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;

  setUp(() {
    messenger.setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method != 'requestPermissions') return null;
      final requested = (call.arguments as List).cast<int>();
      return {for (final p in requested) p: 1};
    });

    client = buildCallTestClient(
      (request) async => http.Response('{"event_id":"\$evt"}', 200),
    );
    room = buildTestRoom(client);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(permissionChannel, null);
  });

  Uint8List testKey() => Uint8List.fromList(List<int>.generate(32, (i) => i));

  Event remoteMemberEvent(
    Room r, {
    required String userId,
    required String deviceId,
    required String callId,
    Map<String, Object?> fociActive = const <String, Object?>{},
  }) {
    final expiresAtMs = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    return buildTestEvent(
      r,
      eventId: '\$member_$userId',
      senderId: userId,
      type: callMemberEventType,
      stateKey: userId,
      content: {
        'memberships': [
          {
            'call_id': callId,
            'device_id': deviceId,
            'kind': 'voice',
            'expires_ts': expiresAtMs,
            'foci_active': fociActive,
          },
        ],
      },
    );
  }

  void registerDevice(
    Client c, {
    required String userId,
    required String deviceId,
    required String curveKey,
  }) {
    final device = _TestDeviceKeys({
      'user_id': userId,
      'device_id': deviceId,
      'algorithms': <String>[],
      'keys': {
        'curve25519:$deviceId': curveKey,
        'ed25519:$deviceId': 'ed25519-$deviceId',
      },
      'signatures': <String, dynamic>{},
    }, c);
    (c.userDeviceKeys[userId] ??= DeviceKeysList(
      userId,
      c,
    )).deviceKeys[deviceId] = device;
  }

  ToDeviceEvent encryptedKeyEvent({
    required String sender,
    required String curveKey,
    required String callId,
    required Uint8List key,
  }) => ToDeviceEvent(
    sender: sender,
    type: callEncryptionKeyEventType,
    content: buildCallEncryptionKeyContent(callId: callId, key: key),
    encryptedContent: {'sender_key': curveKey, 'algorithm': 'm.olm.v1'},
  );

  group('happy path', () {
    test(
      'a call whose engine accepts the key and joins reaches active',
      () async {
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call1',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
          initialEncryptionKeyForTesting: testKey(),
        );
        addTearDown(session.dispose);

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

    test(
      'receiving the call key republishes membership as encrypted',
      () async {
        final published = <Map<String, dynamic>>[];
        final capturing = buildCallTestClient((request) async {
          if (request.method == 'PUT' &&
              request.url.path.contains(callMemberEventType)) {
            published.add(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return http.Response('{"event_id":"\$evt"}', 200);
        });
        final capturingRoom = buildTestRoom(capturing);

        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: capturingRoom,
          callId: 'call-enc',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        registerDevice(
          capturing,
          userId: '@caller:example.org',
          deviceId: 'CALLERDEV',
          curveKey: 'curve-caller',
        );
        capturingRoom.setState(
          remoteMemberEvent(
            capturingRoom,
            userId: '@caller:example.org',
            deviceId: 'CALLERDEV',
            callId: 'call-enc',
          ),
        );
        await session.accept();
        final before = published.length;
        expect(
          published.last['memberships'][0]['foci_active']['encrypted'],
          isFalse,
        );

        capturing.onToDeviceEvent.add(
          encryptedKeyEvent(
            sender: '@caller:example.org',
            curveKey: 'curve-caller',
            callId: 'call-enc',
            key: testKey(),
          ),
        );
        await pumpEventQueue();

        expect(published.length, before + 1);
        expect(
          published.last['memberships'][0]['foci_active']['encrypted'],
          isTrue,
        );
      },
    );
  });

  group('sad paths', () {
    test('a call whose encryption mechanism cannot encrypt the packets fails with an error', () async {
      final engine = FakeCallEngine(failSetEncryptionKey: true);
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call2',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: testKey(),
      );
      addTearDown(session.dispose);

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
        final engine = FakeCallEngine(failSetEncryptionKey: true);
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-key-late-fail',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        registerDevice(
          client,
          userId: '@caller:example.org',
          deviceId: 'CALLERDEV',
          curveKey: 'curve-caller',
        );
        room.setState(
          remoteMemberEvent(
            room,
            userId: '@caller:example.org',
            deviceId: 'CALLERDEV',
            callId: 'call-key-late-fail',
          ),
        );

        await session.accept();
        expect(session.phase, CallSessionPhase.active);

        client.onToDeviceEvent.add(
          encryptedKeyEvent(
            sender: '@caller:example.org',
            curveKey: 'curve-caller',
            callId: 'call-key-late-fail',
            key: testKey(),
          ),
        );
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failedMessage, 'Call did not connect');
      },
    );

    test(
      'a hangup while the engine is still joining is not reported as a failure',
      () async {
        final gate = Completer<void>();
        final engine = FakeCallEngine(failJoin: true, joinGate: gate);
        final sendRoom = _FakeSendEventRoom(
          client: client,
          id: '!hangup-race:example.org',
        );
        final session = CallSession.forIncoming(
          room: sendRoom,
          callId: 'call-hangup-race',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);

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

    test(
      'a call whose engine fails to join also fails with an error',
      () async {
        final engine = FakeCallEngine(failJoin: true);
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call3',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);

        await expectLater(session.accept(), throwsA(isA<StateError>()));

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failedMessage, 'Call did not connect');
      },
    );

    test('a half-built engine is torn down when the connect fails', () async {
      final engine = FakeCallEngine(failJoin: true);
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-teardown',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await expectLater(session.accept(), throwsA(isA<StateError>()));

      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
    });

    test('a room-permission failure surfaces a specific message', () async {
      final engine = FakeCallEngine(
        failJoin: true,
        joinError: MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': "You don't have permission to post that to the room. user_level (0) < send_level (50)",
        }),
      );
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call7',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await expectLater(session.accept(), throwsA(isA<MatrixException>()));

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(
        session.failedMessage,
        'You do not have permission to start calls in this room',
      );
    });

    test('a denied microphone permission fails the call before ever building an engine', () async {
      messenger.setMockMethodCallHandler(permissionChannel, (call) async {
        if (call.method != 'requestPermissions') return null;
        final requested = (call.arguments as List).cast<int>();
        return {for (final p in requested) p: 0};
      });

      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call4',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await expectLater(session.accept(), throwsA(isA<StateError>()));

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(engine.joined, isFalse);
    });

    test(
      'an engine that gives up reconnecting ends the call as failed',
      () async {
        final engine = FakeCallEngine();
        final sendRoom = _FakeSendEventRoom(
          client: client,
          id: '!lost:example.org',
        );
        final session = CallSession.forIncoming(
          room: sendRoom,
          callId: 'call-lost',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        await session.accept();
        expect(session.phase, CallSessionPhase.active);

        engine.statusController.add(CallEngineStatus.failed);
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failedMessage, 'Connection lost');
        expect(sendRoom.sentEvents.last['call_id'], 'call-lost');
      },
    );

    test(
      'a permission denial while the engine build also fails ends cleanly',
      () async {
        messenger.setMockMethodCallHandler(permissionChannel, (call) async {
          if (call.method != 'requestPermissions') return null;
          final requested = (call.arguments as List).cast<int>();
          return {for (final p in requested) p: 0};
        });
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-double-fail',
          kind: CallKind.voice,
          engineBuilder: () async => throw StateError('gateway down'),
        );
        addTearDown(session.dispose);

        await expectLater(session.accept(), throwsStateError);

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
      },
    );

    test('a failed status that arrives while connecting is finishing does not get overwritten back to active', () async {
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
      final raceRoom = _FakeSendEventRoom(
        client: raceClient,
        id: '!race:example.org',
      );

      final session = CallSession.forIncoming(
        room: raceRoom,
        callId: 'call-race',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await session.accept();

      expect(session.phase, CallSessionPhase.ended);
      expect(session.endReason, CallEndReason.failed);
      expect(session.failedMessage, 'Connection lost');

      final callsBeforeSeed = engine.updateRemoteParticipantCalls;
      raceRoom.setState(
        remoteMemberEvent(
          raceRoom,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-race',
        ),
      );
      raceClient.onSync.add(SyncUpdate(nextBatch: 'after-end'));
      await pumpEventQueue();

      expect(engine.updateRemoteParticipantCalls, callsBeforeSeed);
    });
  });

  group('ensurePermissions', () {
    test(
      'memoized: two callers share exactly one underlying request',
      () async {
        var requestCount = 0;
        messenger.setMockMethodCallHandler(permissionChannel, (call) async {
          if (call.method != 'requestPermissions') return null;
          requestCount++;
          final requested = (call.arguments as List).cast<int>();
          return {for (final p in requested) p: 1};
        });

        final session = CallSession.forIncoming(
          room: room,
          callId: 'call5',
          kind: CallKind.voice,
          engineBuilder: () async => FakeCallEngine(),
        );
        addTearDown(session.dispose);

        final first = session.ensurePermissions();
        final second = session.ensurePermissions();
        await Future.wait([first, second]);

        expect(requestCount, 1);
      },
    );

    test(
      'a rejected request stays rejected for every caller, not just the first',
      () async {
        messenger.setMockMethodCallHandler(permissionChannel, (call) async {
          if (call.method != 'requestPermissions') return null;
          final requested = (call.arguments as List).cast<int>();
          return {for (final p in requested) p: 0};
        });

        final session = CallSession.forIncoming(
          room: room,
          callId: 'call6',
          kind: CallKind.voice,
          engineBuilder: () async => FakeCallEngine(),
        );
        addTearDown(session.dispose);

        await expectLater(
          session.ensurePermissions(),
          throwsA(isA<StateError>()),
        );
        await expectLater(session.accept(), throwsA(isA<StateError>()));
        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
      },
    );
  });

  group('_generateCallKey (via startOutgoing)', () {
    test(
      'produces a 32-byte key, and two calls never produce the same one',
      () async {
        final sendRoom = _FakeSendEventRoom(
          client: client,
          id: '!room:example.org',
        );
        final engineA = FakeCallEngine();
        final sessionA = CallSession.startOutgoing(
          sendRoom,
          CallKind.voice,
          engineBuilder: () async => engineA,
        );
        addTearDown(sessionA.dispose);
        await sessionA.phaseStream.firstWhere(
          (p) => p == CallSessionPhase.active,
        );

        final engineB = FakeCallEngine();
        final sessionB = CallSession.startOutgoing(
          sendRoom,
          CallKind.voice,
          engineBuilder: () async => engineB,
        );
        addTearDown(sessionB.dispose);
        await sessionB.phaseStream.firstWhere(
          (p) => p == CallSessionPhase.active,
        );

        expect(engineA.appliedKey, isNotNull);
        expect(engineA.appliedKey, hasLength(32));
        expect(engineB.appliedKey, isNotNull);
        expect(engineB.appliedKey, hasLength(32));
        expect(engineA.appliedKey, isNot(engineB.appliedKey));
      },
    );
  });

  group('callee applying a key that arrives over real to-device', () {
    test('a key delivered via client.onToDeviceEvent after the session is already active is applied retroactively', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-td-1',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      registerDevice(
        client,
        userId: '@caller:example.org',
        deviceId: 'CALLERDEV',
        curveKey: 'curve-caller',
      );
      room.setState(
        remoteMemberEvent(
          room,
          userId: '@caller:example.org',
          deviceId: 'CALLERDEV',
          callId: 'call-td-1',
        ),
      );

      await session.accept();
      expect(engine.appliedKey, isNull);

      final key = testKey();
      client.onToDeviceEvent.add(
        encryptedKeyEvent(
          sender: '@caller:example.org',
          curveKey: 'curve-caller',
          callId: 'call-td-1',
          key: key,
        ),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, key);
    });

    test('an unencrypted key event is rejected', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-td-plain',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      registerDevice(
        client,
        userId: '@caller:example.org',
        deviceId: 'CALLERDEV',
        curveKey: 'curve-caller',
      );
      room.setState(
        remoteMemberEvent(
          room,
          userId: '@caller:example.org',
          deviceId: 'CALLERDEV',
          callId: 'call-td-plain',
        ),
      );
      await session.accept();

      client.onToDeviceEvent.add(
        ToDeviceEvent(
          sender: '@caller:example.org',
          type: callEncryptionKeyEventType,
          content: buildCallEncryptionKeyContent(
            callId: 'call-td-plain',
            key: testKey(),
          ),
        ),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, isNull);
      expect(session.isEncrypted, isFalse);
    });

    test('a key from a device that is not in the call is rejected', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-td-outsider',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      registerDevice(
        client,
        userId: '@mallory:example.org',
        deviceId: 'MALDEV',
        curveKey: 'curve-mallory',
      );
      await session.accept();

      client.onToDeviceEvent.add(
        encryptedKeyEvent(
          sender: '@mallory:example.org',
          curveKey: 'curve-mallory',
          callId: 'call-td-outsider',
          key: testKey(),
        ),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, isNull);
    });

    test(
      'a key whose sender_key belongs to a different user is rejected',
      () async {
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-td-spoof',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        registerDevice(
          client,
          userId: '@mallory:example.org',
          deviceId: 'MALDEV',
          curveKey: 'curve-mallory',
        );
        room.setState(
          remoteMemberEvent(
            room,
            userId: '@caller:example.org',
            deviceId: 'CALLERDEV',
            callId: 'call-td-spoof',
          ),
        );
        await session.accept();

        client.onToDeviceEvent.add(
          encryptedKeyEvent(
            sender: '@caller:example.org',
            curveKey: 'curve-mallory',
            callId: 'call-td-spoof',
            key: testKey(),
          ),
        );
        await pumpEventQueue();

        expect(engine.appliedKey, isNull);
      },
    );

    test(
      'a key arriving before the sender\'s membership is applied once it lands',
      () async {
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-td-race',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        registerDevice(
          client,
          userId: '@caller:example.org',
          deviceId: 'CALLERDEV',
          curveKey: 'curve-caller',
        );
        await session.accept();

        final key = testKey();
        client.onToDeviceEvent.add(
          encryptedKeyEvent(
            sender: '@caller:example.org',
            curveKey: 'curve-caller',
            callId: 'call-td-race',
            key: key,
          ),
        );
        await pumpEventQueue();
        expect(engine.appliedKey, isNull);

        room.setState(
          remoteMemberEvent(
            room,
            userId: '@caller:example.org',
            deviceId: 'CALLERDEV',
            callId: 'call-td-race',
          ),
        );
        client.onSync.add(SyncUpdate(nextBatch: 'b1'));
        await pumpEventQueue();

        expect(engine.appliedKey, key);
        expect(session.isEncrypted, isTrue);
      },
    );

    test('a to-device event for a different call_id is ignored', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-td-2',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      await session.accept();

      client.onToDeviceEvent.add(
        ToDeviceEvent(
          sender: '@caller:example.org',
          type: callEncryptionKeyEventType,
          content: buildCallEncryptionKeyContent(
            callId: 'some-other-call',
            key: testKey(),
          ),
        ),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, isNull);
    });

    test('a malformed to-device event (bad type, bad base64, missing fields) is ignored, not crashed on', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-td-3',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      await session.accept();

      client.onToDeviceEvent.add(
        ToDeviceEvent(
          sender: '@caller:example.org',
          type: 'm.some.other.event',
          content: {'call_id': 'call-td-3', 'key': base64Encode(testKey())},
        ),
      );
      client.onToDeviceEvent.add(
        ToDeviceEvent(
          sender: '@caller:example.org',
          type: callEncryptionKeyEventType,
          content: {'call_id': 'call-td-3', 'key': 'not valid base64!!'},
        ),
      );
      client.onToDeviceEvent.add(
        ToDeviceEvent(
          sender: '@caller:example.org',
          type: callEncryptionKeyEventType,
          content: {'call_id': 'call-td-3'},
        ),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, isNull);
      expect(session.phase, CallSessionPhase.active);
    });

    test('a second to-device event with a different key is ignored — exactly one key per call', () async {
      final engine = FakeCallEngine();
      final firstKey = testKey();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-td-4',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: firstKey,
      );
      addTearDown(session.dispose);
      await session.accept();
      expect(engine.appliedKey, firstKey);

      final secondKey = Uint8List.fromList(
        List<int>.generate(32, (i) => 255 - i),
      );
      client.onToDeviceEvent.add(
        ToDeviceEvent(
          sender: '@caller:example.org',
          type: callEncryptionKeyEventType,
          content: buildCallEncryptionKeyContent(
            callId: 'call-td-4',
            key: secondKey,
          ),
        ),
      );
      await pumpEventQueue();

      expect(engine.appliedKey, firstKey);
    });
  });

  group('caller relaying the key to newly-discovered devices', () {
    late List<http.Request> requests;
    late Map<String, Object?> keysQueryResponse;

    Client buildClientWithRequestLog() {
      requests = [];
      return buildCallTestClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/keys/query')) {
          return http.Response(jsonEncode(keysQueryResponse), 200);
        }
        return http.Response('{"event_id":"\$evt"}', 200);
      });
    }

    setUp(() {
      keysQueryResponse = const {'device_keys': {}};
    });

    test('a session with no key yet does not call updateUserDeviceKeys/sendToDeviceEncrypted at all', () async {
      final c = buildClientWithRequestLog();
      final r = buildTestRoom(c);
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: r,
        callId: 'call-relay-1',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-1',
        ),
      );

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(
        requests.any((rq) => rq.url.path.endsWith('/keys/query')),
        isFalse,
      );
    });

    test('a session that already holds a key attempts the relay (updateUserDeviceKeys) the moment a new device is discovered', () async {
      keysQueryResponse = {
        'device_keys': {
          '@bob:example.org': {
            'BOBDEVICE': {
              'user_id': '@bob:example.org',
              'device_id': 'BOBDEVICE',
              'algorithms': ['m.olm.v1.curve25519-aes-sha2'],
              'keys': {
                'curve25519:BOBDEVICE': 'fakeCurve25519Key',
                'ed25519:BOBDEVICE': 'fakeEd25519Key',
              },
              'signatures': {
                '@bob:example.org': {'ed25519:BOBDEVICE': 'fakeSignature'},
              },
            },
          },
        },
      };
      final c = buildClientWithRequestLog();
      final r = buildTestRoom(c);
      final engine = FakeCallEngine();
      final key = testKey();
      final session = CallSession.forIncoming(
        room: r,
        callId: 'call-relay-2',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: key,
      );
      addTearDown(session.dispose);

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-2',
        ),
      );

      await session.accept();
      await pumpEventQueue();

      final queryRequests = requests.where(
        (rq) => rq.url.path.endsWith('/keys/query'),
      );
      expect(queryRequests, isNotEmpty);
      final body = jsonDecode(
        utf8.decode(queryRequests.first.bodyBytes),
      ) as Map<String, Object?>;
      final deviceKeysRequested = (body['device_keys'] as Map)
          .cast<String, Object?>();
      expect(deviceKeysRequested.containsKey('@bob:example.org'), isTrue);

      expect(
        c.userDeviceKeys['@bob:example.org']?.deviceKeys['BOBDEVICE'],
        isNull,
      );
      expect(session.phase, CallSessionPhase.active);
    });

    test(
      'a failed device-key fetch is retried before the relay gives up',
      () async {
        const bobDeviceKeys = {
          'device_keys': {
            '@bob:example.org': {
              'BOBDEVICE': {
                'user_id': '@bob:example.org',
                'device_id': 'BOBDEVICE',
                'algorithms': ['m.olm.v1.curve25519-aes-sha2'],
                'keys': {
                  'curve25519:BOBDEVICE': 'fakeCurve25519Key',
                  'ed25519:BOBDEVICE': 'fakeEd25519Key',
                },
                'signatures': {
                  '@bob:example.org': {'ed25519:BOBDEVICE': 'fakeSignature'},
                },
              },
            },
          },
        };
        var keysQueries = 0;
        final c = buildCallTestClient((request) async {
          if (request.url.path.endsWith('/keys/query')) {
            keysQueries++;
            if (keysQueries == 1) return http.Response('boom', 500);
            return http.Response(jsonEncode(bobDeviceKeys), 200);
          }
          return http.Response('{"event_id":"\$evt"}', 200);
        });
        final r = buildTestRoom(c);
        final session = CallSession.forIncoming(
          room: r,
          callId: 'call-relay-retry',
          kind: CallKind.voice,
          engineBuilder: () async => FakeCallEngine(),
          initialEncryptionKeyForTesting: testKey(),
          keyRelayBaseDelay: Duration.zero,
          keyRelayMaxDelay: Duration.zero,
        );
        addTearDown(session.dispose);
        r.setState(
          remoteMemberEvent(
            r,
            userId: '@bob:example.org',
            deviceId: 'BOBDEVICE',
            callId: 'call-relay-retry',
          ),
        );

        await session.accept();
        await pumpEventQueue(times: 50);

        expect(keysQueries, greaterThanOrEqualTo(2));
      },
    );

    test('no device keys found for the remote device is a safe no-op (not a crash)', () async {
      final c = buildClientWithRequestLog();
      final r = buildTestRoom(c);
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: r,
        callId: 'call-relay-3',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: testKey(),
      );
      addTearDown(session.dispose);

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-3',
        ),
      );

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(
        c.userDeviceKeys['@bob:example.org']?.deviceKeys['BOBDEVICE'],
        isNull,
      );
    });

    test('the same remote device seen across two reconcile passes only triggers one relay attempt', () async {
      final c = buildClientWithRequestLog();
      final r = buildTestRoom(c);
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: r,
        callId: 'call-relay-4',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: testKey(),
      );
      addTearDown(session.dispose);

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-4',
        ),
      );

      await session.accept();
      await pumpEventQueue();
      final firstPassQueries = requests
          .where((rq) => rq.url.path.endsWith('/keys/query'))
          .length;
      expect(firstPassQueries, greaterThan(0));

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-4',
        ),
      );
      c.onSync.add(SyncUpdate(nextBatch: 'batch2'));
      await pumpEventQueue();

      final totalQueries = requests
          .where((rq) => rq.url.path.endsWith('/keys/query'))
          .length;
      expect(totalQueries, firstPassQueries);
    });

    test(
      'a known device that re-joins with a new sessionId is sent the key again',
      () async {
        final c = buildClientWithRequestLog();
        final r = buildTestRoom(c);
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: r,
          callId: 'call-relay-5',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
          initialEncryptionKeyForTesting: testKey(),
        );
        addTearDown(session.dispose);

        r.setState(
          remoteMemberEvent(
            r,
            userId: '@bob:example.org',
            deviceId: 'BOBDEVICE',
            callId: 'call-relay-5',
            fociActive: const {'sessionId': 'bob-session-1'},
          ),
        );

        await session.accept();
        await pumpEventQueue();
        final firstPassQueries = requests
            .where((rq) => rq.url.path.endsWith('/keys/query'))
            .length;
        expect(firstPassQueries, greaterThan(0));

        r.setState(
          remoteMemberEvent(
            r,
            userId: '@bob:example.org',
            deviceId: 'BOBDEVICE',
            callId: 'call-relay-5',
            fociActive: const {'sessionId': 'bob-session-2'},
          ),
        );
        c.onSync.add(SyncUpdate(nextBatch: 'batch2'));
        await pumpEventQueue();

        final totalQueries = requests
            .where((rq) => rq.url.path.endsWith('/keys/query'))
            .length;
        expect(totalQueries, greaterThan(firstPassQueries));
      },
    );

    test('a known device republishing the same sessionId is not sent the key again', () async {
      final c = buildClientWithRequestLog();
      final r = buildTestRoom(c);
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: r,
        callId: 'call-relay-6',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: testKey(),
        keyRelayBaseDelay: Duration.zero,
        keyRelayMaxDelay: Duration.zero,
      );
      addTearDown(session.dispose);

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-6',
          fociActive: const {'sessionId': 'bob-session-1', 'audioMuted': false},
        ),
      );

      await session.accept();
      await pumpEventQueue(times: 50);
      final firstPassQueries = requests
          .where((rq) => rq.url.path.endsWith('/keys/query'))
          .length;
      expect(firstPassQueries, greaterThan(0));

      r.setState(
        remoteMemberEvent(
          r,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-relay-6',
          fociActive: const {'sessionId': 'bob-session-1', 'audioMuted': true},
        ),
      );
      c.onSync.add(SyncUpdate(nextBatch: 'batch2'));
      await pumpEventQueue();

      final totalQueries = requests
          .where((rq) => rq.url.path.endsWith('/keys/query'))
          .length;
      expect(totalQueries, firstPassQueries);
    });
  });

  group('everHadRemote / remoteJoinedStream', () {
    test('connecting to the SFU alone is not the other end joining', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-remote-1',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(session.everHadRemote, isFalse);
    });

    test('a remote membership flips it, and fires the stream once', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-remote-2',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      final joins = <void>[];
      session.remoteJoinedStream.listen(joins.add);

      room.setState(
        remoteMemberEvent(
          room,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-remote-2',
        ),
      );
      await session.accept();
      await pumpEventQueue();

      expect(session.everHadRemote, isTrue);
      expect(joins, hasLength(1));
    });

    test('a republished membership does not fire it again', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-remote-3',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      final joins = <void>[];
      session.remoteJoinedStream.listen(joins.add);

      room.setState(
        remoteMemberEvent(
          room,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-remote-3',
        ),
      );
      await session.accept();
      await pumpEventQueue();

      room.setState(
        remoteMemberEvent(
          room,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-remote-3',
        ),
      );
      client.onSync.add(SyncUpdate(nextBatch: 'batch2'));
      await pumpEventQueue();

      expect(joins, hasLength(1));
    });

    test(
      'a membership for a different call is not this call answered',
      () async {
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-remote-4',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);

        final joins = <void>[];
        session.remoteJoinedStream.listen(joins.add);

        room.setState(
          remoteMemberEvent(
            room,
            userId: '@bob:example.org',
            deviceId: 'BOBDEVICE',
            callId: 'some-other-call',
          ),
        );
        await session.accept();
        await pumpEventQueue();

        expect(session.everHadRemote, isFalse);
        expect(joins, isEmpty);
      },
    );
  });

  group('_connect key-before-join ordering', () {
    test(
      'the caller-side key is applied before join() is ever called',
      () async {
        final calls = <String>[];
        final engine = _OrderTrackingCallEngine(calls);
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-order-1',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
          initialEncryptionKeyForTesting: testKey(),
        );
        addTearDown(session.dispose);

        await session.accept();

        expect(calls, ['setEncryptionKey', 'join']);
      },
    );

    test('a callee with no key yet joins without ever calling setEncryptionKey first', () async {
      final calls = <String>[];
      final engine = _OrderTrackingCallEngine(calls);
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-order-2',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await session.accept();

      expect(calls, ['join']);
    });
  });

  group('membership republish throttling', () {
    Future<
      ({CallSession session, List<String> publishes, FakeCallEngine engine})
    >
    startCountingSession(String callId) async {
      final publishes = <String>[];
      final c = buildCallTestClient((request) async {
        if (request.url.path.contains(callMemberEventType)) {
          publishes.add(request.body);
        }
        return http.Response('{"event_id":"\$evt"}', 200);
      });
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: buildTestRoom(c),
        callId: callId,
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      await session.accept();
      await pumpEventQueue();
      return (session: session, publishes: publishes, engine: engine);
    }

    test('connecting publishes membership exactly once', () async {
      final r = await startCountingSession('call-pub-1');
      addTearDown(r.session.dispose);
      expect(r.publishes, hasLength(1));
    });

    test('a refresh carrying nothing new does not republish', () async {
      final r = await startCountingSession('call-pub-2');
      addTearDown(r.session.dispose);
      final before = r.publishes.length;

      await r.session.refreshMembership();
      await r.session.refreshMembership();
      await r.session.refreshMembership();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await pumpEventQueue();

      expect(r.publishes.length, before);
    });

    test('a refresh after a real change does republish, once', () async {
      final r = await startCountingSession('call-pub-3');
      addTearDown(r.session.dispose);
      final before = r.publishes.length;

      r.engine.micMuted = true;
      await r.session.refreshMembership();
      await r.session.refreshMembership();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await pumpEventQueue();

      expect(r.publishes.length, before + 1);
      expect(r.publishes.last, contains('audioMuted'));
    });

    test('a real change is published at once, not after the window', () async {
      final r = await startCountingSession('call-pub-4');
      addTearDown(r.session.dispose);
      final before = r.publishes.length;

      r.engine.micMuted = true;
      await r.session.refreshMembership();
      await pumpEventQueue();

      expect(r.publishes.length, before + 1);
      expect(r.publishes.last, contains('"audioMuted":true'));
    });

    test('changes inside the window coalesce into one trailing publish '
        'carrying the final state', () async {
      final r = await startCountingSession('call-pub-5');
      addTearDown(r.session.dispose);
      final before = r.publishes.length;

      r.engine.micMuted = true;
      await r.session.refreshMembership();
      r.engine.micMuted = false;
      await r.session.refreshMembership();
      r.engine.micMuted = true;
      await r.session.refreshMembership();
      r.engine.micMuted = false;
      await r.session.refreshMembership();
      await pumpEventQueue();
      expect(r.publishes.length, before + 1);

      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await pumpEventQueue();

      expect(r.publishes.length, before + 2);
      expect(r.publishes.last, contains('"audioMuted":false'));
    });
  });

  group('decline authorisation', () {
    Event declineEvent(
      Room r, {
      required String senderId,
      required String callId,
    }) => buildTestEvent(
      r,
      eventId: '\$decline_$senderId',
      senderId: senderId,
      content: {
        'msgtype': callDeclineMsgtype,
        'body': 'Call declined',
        'call_id': callId,
      },
    );

    test('a decline is ignored once someone has joined the call', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-dec-1',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      room.setState(
        remoteMemberEvent(
          room,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-dec-1',
        ),
      );
      await session.accept();
      await pumpEventQueue();
      expect(session.everHadRemote, isTrue);

      client.onTimelineEvent.add(
        declineEvent(
          room,
          senderId: '@mallory:example.org',
          callId: 'call-dec-1',
        ),
      );
      await pumpEventQueue();

      expect(session.phase, isNot(CallSessionPhase.ended));
    });

    test('our own decline echoed back does not end the call', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-dec-2',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      await session.accept();
      await pumpEventQueue();

      client.onTimelineEvent.add(
        declineEvent(room, senderId: '@me:example.org', callId: 'call-dec-2'),
      );
      await pumpEventQueue();

      expect(session.phase, isNot(CallSessionPhase.ended));
    });
  });

  group('ending a call', () {
    ({CallSession session, FakeCallEngine engine, _FakeSendEventRoom room})
    buildActiveCall(String callId) {
      final sendRoom = _FakeSendEventRoom(
        client: client,
        id: '!room:example.org',
      );
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: sendRoom,
        callId: callId,
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        initialEncryptionKeyForTesting: null,
      );
      return (session: session, engine: engine, room: sendRoom);
    }

    int summariesIn(_FakeSendEventRoom room) => room.sentEvents
        .where((content) => content['msgtype'] == callSummaryMsgtype)
        .length;

    test('hanging up tears the call down exactly once', () async {
      final call = buildActiveCall('hangup-once');
      addTearDown(call.session.dispose);
      await call.session.accept();

      await call.session.hangUp();

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.engine.leaveCalls, 1);
      expect(call.engine.disposeCalls, 1);
      expect(summariesIn(call.room), 1);
    });

    test(
      'two hang-ups landing at once still tear it down exactly once',
      () async {
        final call = buildActiveCall('hangup-race');
        addTearDown(call.session.dispose);
        await call.session.accept();

        await expectLater(
          Future.wait([call.session.hangUp(), call.session.hangUp()]),
          completes,
        );
        await pumpEventQueue();

        expect(call.session.phase, CallSessionPhase.ended);
        expect(call.engine.leaveCalls, 1);
        expect(call.engine.disposeCalls, 1);
        expect(summariesIn(call.room), 1);
      },
    );

    test(
      'a hang-up resuming after the engine is disposed never reaches it',
      () async {
        final firstClearArrived = Completer<void>();
        final releaseFirstClear = Completer<void>();
        var clears = 0;
        final gatedClient = buildCallTestClient((request) async {
          if (request.method == 'PUT' &&
              request.url.path.contains(callMemberEventType) &&
              request.body.contains('"memberships":[]')) {
            clears++;
            if (clears == 1) {
              firstClearArrived.complete();
              await releaseFirstClear.future;
            }
          }
          return http.Response('{"event_id":"\$evt"}', 200);
        });

        final sendRoom = _FakeSendEventRoom(
          client: gatedClient,
          id: '!room:example.org',
        );
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: sendRoom,
          callId: 'hangup-late',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        await session.accept();

        final first = session.hangUp();
        await firstClearArrived.future;

        final second = session.hangUp();
        await pumpEventQueue();

        releaseFirstClear.complete();
        await expectLater(Future.wait([first, second]), completes);
        await pumpEventQueue();

        expect(clears, 1);
        expect(engine.leaveCalls, 1);
        expect(engine.disposeCalls, 1);
        expect(summariesIn(sendRoom), 1);
      },
    );

    test('hanging up a call that has already ended changes nothing', () async {
      final call = buildActiveCall('hangup-twice');
      addTearDown(call.session.dispose);
      await call.session.accept();

      await call.session.hangUp();
      await call.session.hangUp();

      expect(call.engine.leaveCalls, 1);
      expect(call.engine.disposeCalls, 1);
      expect(summariesIn(call.room), 1);
    });

    ({_FakeSendEventRoom room, List<String> memberPuts})
    roomLoggingMemberPuts() {
      final memberPuts = <String>[];
      final logging = buildCallTestClient((request) async {
        if (request.method == 'PUT' &&
            request.url.path.contains(callMemberEventType)) {
          memberPuts.add(request.body);
        }
        return http.Response('{"event_id":"\$evt"}', 200);
      });
      return (
        room: _FakeSendEventRoom(client: logging, id: '!room:example.org'),
        memberPuts: memberPuts,
      );
    }

    test('an engine built after the hangup is torn down, not joined', () async {
      final (room: sendRoom, :memberPuts) = roomLoggingMemberPuts();
      final engine = FakeCallEngine();
      final buildGate = Completer<void>();
      final session = CallSession.forIncoming(
        room: sendRoom,
        callId: 'hangup-during-build',
        kind: CallKind.voice,
        engineBuilder: () async {
          await buildGate.future;
          return engine;
        },
      );
      addTearDown(session.dispose);

      final accepting = session.accept();
      await pumpEventQueue();
      await session.hangUp();
      final putsAtHangup = memberPuts.length;

      buildGate.complete();
      await accepting;
      await pumpEventQueue();

      expect(engine.joined, isFalse);
      expect(engine.leaveCalls, 1);
      expect(engine.disposeCalls, 1);
      expect(memberPuts, hasLength(putsAtHangup));
      expect(memberPuts.last, contains('"memberships":[]'));
      expect(session.phase, CallSessionPhase.ended);
      expect(summariesIn(sendRoom), 1);
    });

    test(
      'a join completing after the hangup does not republish membership',
      () async {
        final (room: sendRoom, :memberPuts) = roomLoggingMemberPuts();
        final joinGate = Completer<void>();
        final engine = FakeCallEngine(joinGate: joinGate);
        final session = CallSession.forIncoming(
          room: sendRoom,
          callId: 'hangup-during-join',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);

        final accepting = session.accept();
        await pumpEventQueue();
        await session.hangUp();
        final putsAtHangup = memberPuts.length;

        joinGate.complete();
        await accepting;
        await pumpEventQueue();

        expect(engine.leaveCalls, 1);
        expect(engine.disposeCalls, 1);
        expect(memberPuts, hasLength(putsAtHangup));
        expect(memberPuts.last, contains('"memberships":[]'));
        expect(session.phase, CallSessionPhase.ended);
        expect(summariesIn(sendRoom), 1);
      },
    );
  });

  group('auto-hangup when the remote membership reads empty', () {
    Future<
      ({CallSession session, FakeCallEngine engine, _FakeSendEventRoom room})
    >
    startJoinedCall(String callId, {Duration? remoteLeftConfirmDelay}) async {
      final sendRoom = _FakeSendEventRoom(
        client: client,
        id: '!room:example.org',
      );
      sendRoom.setState(
        remoteMemberEvent(
          sendRoom,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: callId,
        ),
      );
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: sendRoom,
        callId: callId,
        kind: CallKind.voice,
        engineBuilder: () async => engine,
        remoteLeftConfirmDelay: remoteLeftConfirmDelay,
      );
      await session.accept();
      await pumpEventQueue();
      expect(
        session.everHadRemote,
        isTrue,
        reason: 'setup: the initial reconcile pass should have seen Bob',
      );
      return (session: session, engine: engine, room: sendRoom);
    }

    void bobLeaves(_FakeSendEventRoom room, String callId) => room.setState(
      buildTestEvent(
        room,
        eventId: r'$bob-left',
        senderId: '@bob:example.org',
        type: callMemberEventType,
        stateKey: '@bob:example.org',
        content: const {'memberships': <Object?>[]},
      ),
    );

    test('does not hang up on a single empty reconciliation pass', () async {
      final call = await startJoinedCall('call-empty-1');
      addTearDown(call.session.dispose);

      bobLeaves(call.room, 'call-empty-1');
      client.onSync.add(SyncUpdate(nextBatch: 'b1'));
      await pumpEventQueue();

      expect(call.session.phase, CallSessionPhase.active);
      expect(call.engine.leaveCalls, 0);
    });

    test('hangs up once the empty reconciliation is confirmed on a second '
        'consecutive pass', () async {
      final call = await startJoinedCall('call-empty-2');
      addTearDown(call.session.dispose);

      bobLeaves(call.room, 'call-empty-2');
      client.onSync.add(SyncUpdate(nextBatch: 'b1'));
      await pumpEventQueue();
      client.onSync.add(SyncUpdate(nextBatch: 'b2'));
      await pumpEventQueue();

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.engine.leaveCalls, 1);
    });

    test('confirms the empty pass on a timer, so a hang-up is noticed '
        'without waiting for unrelated sync traffic', () async {
      final call = await startJoinedCall(
        'call-empty-timer',
        remoteLeftConfirmDelay: const Duration(milliseconds: 10),
      );
      addTearDown(call.session.dispose);

      bobLeaves(call.room, 'call-empty-timer');
      client.onSync.add(SyncUpdate(nextBatch: 'b1'));
      await pumpEventQueue();
      expect(call.session.phase, CallSessionPhase.active);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();

      expect(call.session.phase, CallSessionPhase.ended);
      expect(call.engine.leaveCalls, 1);
    });

    test('a remote that reappears before the timer fires cancels the '
        'confirmation', () async {
      final call = await startJoinedCall(
        'call-empty-timer-2',
        remoteLeftConfirmDelay: const Duration(milliseconds: 30),
      );
      addTearDown(call.session.dispose);

      bobLeaves(call.room, 'call-empty-timer-2');
      client.onSync.add(SyncUpdate(nextBatch: 'b1'));
      await pumpEventQueue();

      call.room.setState(
        remoteMemberEvent(
          call.room,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-empty-timer-2',
        ),
      );
      client.onSync.add(SyncUpdate(nextBatch: 'b2'));
      await pumpEventQueue();

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await pumpEventQueue();

      expect(call.session.phase, CallSessionPhase.active);
      expect(call.engine.leaveCalls, 0);
    });

    test('does not hang up if the remote reappears between two empty passes '
        '— the exact republish-race this guards against', () async {
      final call = await startJoinedCall('call-empty-3');
      addTearDown(call.session.dispose);

      bobLeaves(call.room, 'call-empty-3');
      client.onSync.add(SyncUpdate(nextBatch: 'b1'));
      await pumpEventQueue();

      call.room.setState(
        remoteMemberEvent(
          call.room,
          userId: '@bob:example.org',
          deviceId: 'BOBDEVICE',
          callId: 'call-empty-3',
        ),
      );
      client.onSync.add(SyncUpdate(nextBatch: 'b2'));
      await pumpEventQueue();

      bobLeaves(call.room, 'call-empty-3');
      client.onSync.add(SyncUpdate(nextBatch: 'b3'));
      await pumpEventQueue();

      expect(call.session.phase, CallSessionPhase.active);
      expect(call.engine.leaveCalls, 0);
    });
  });

  group('call capacity', () {
    const callFull = 'This call is full. Up to 6 people can join a call.';

    void joinAs(Room r, String userId, String callId, {int createdAtMs = 0}) =>
        r.setState(
          buildTestEvent(
            r,
            eventId: '\$capacity_$userId',
            senderId: userId,
            type: callMemberEventType,
            stateKey: userId,
            content: {
              'memberships': [
                RtcMembership(
                  callId: callId,
                  deviceId: 'DEVICE',
                  kind: 'voice',
                  expiresAtMs: DateTime.now()
                      .add(const Duration(minutes: 5))
                      .millisecondsSinceEpoch,
                  createdAtMs: createdAtMs,
                  fociActive: const {},
                ).toJson(),
              ],
            },
          ),
        );

    void fill(Room r, String callId, int count) {
      for (var i = 1; i <= count; i++) {
        joinAs(r, '@p$i:example.org', callId, createdAtMs: i);
      }
    }

    test('accepting a call that already has 6 people ends it as full '
        'without building an engine', () async {
      fill(room, 'call-full', 6);
      var engineBuilds = 0;
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-full',
        kind: CallKind.voice,
        engineBuilder: () async {
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

    test('accepting a call with 5 other people connects', () async {
      fill(room, 'call-room', 5);
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-room',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);

      await session.accept();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(session.failedMessage, isNull);
      expect(engine.joined, isTrue);
    });

    test(
      'a joiner who turns out to be 7th leaves without posting a summary',
      () async {
        final sendRoom = _FakeSendEventRoom(
          client: client,
          id: '!room:example.org',
        );
        fill(sendRoom, 'call-race', 5);
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: sendRoom,
          callId: 'call-race',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
        await session.accept();
        await pumpEventQueue();
        expect(session.phase, CallSessionPhase.active);

        joinAs(sendRoom, '@p6:example.org', 'call-race', createdAtMs: 6);
        joinAs(sendRoom, '@me:example.org', 'call-race', createdAtMs: 7);
        client.onSync.add(SyncUpdate(nextBatch: 'race'));
        await pumpEventQueue();

        expect(session.phase, CallSessionPhase.ended);
        expect(session.endReason, CallEndReason.failed);
        expect(session.failedMessage, callFull);
        expect(engine.leaveCalls, 1);
        expect(sendRoom.sentEvents, isEmpty);
      },
    );

    test('an earlier joiner stays when a later one makes it 7', () async {
      final engine = FakeCallEngine();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call-stay',
        kind: CallKind.voice,
        engineBuilder: () async => engine,
      );
      addTearDown(session.dispose);
      fill(room, 'call-stay', 5);
      await session.accept();
      await pumpEventQueue();

      joinAs(room, '@me:example.org', 'call-stay', createdAtMs: 0);
      fill(room, 'call-stay', 6);
      client.onSync.add(SyncUpdate(nextBatch: 'stay'));
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.active);
      expect(engine.leaveCalls, 0);
    });

    test(
      'the published membership keeps one join time across republishes',
      () async {
        final publishes = <String>[];
        final c = buildCallTestClient((request) async {
          if (request.url.path.contains(callMemberEventType)) {
            publishes.add(request.body);
          }
          return http.Response('{"event_id":"\$evt"}', 200);
        });
        final engine = FakeCallEngine();
        final session = CallSession.forIncoming(
          room: buildTestRoom(c),
          callId: 'call-joined-at',
          kind: CallKind.voice,
          engineBuilder: () async => engine,
        );
        addTearDown(session.dispose);
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

  group('module wiring', () {
    const webrtcChannel = MethodChannel('FlutterWebRTC.Method');

    setUp(() {
      messenger.setMockMethodCallHandler(webrtcChannel, (call) async {
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
          default:
            return null;
        }
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(webrtcChannel, null);
    });

    test(
      'the engine and TURN mint hit the Synapse module with the Matrix token, '
      'and the mint never delays session creation',
      () async {
        const base = '/_synapse/client/zuno/calls/cloudflare';
        final requests = <http.Request>[];
        final sessionCreated = Completer<void>();
        var turnAnsweredAfterSession = false;
        final module = MockClient((request) async {
          requests.add(request);
          if (request.url.path == '$base/turn/credentials') {
            await sessionCreated.future.timeout(
              const Duration(seconds: 2),
              onTimeout: () {},
            );
            turnAnsweredAfterSession = sessionCreated.isCompleted;
            return http.Response(jsonEncode({'iceServers': []}), 200);
          }
          if (!sessionCreated.isCompleted) sessionCreated.complete();
          return http.Response(jsonEncode({'sessionId': 's1'}), 200);
        });
        client.homeserver = Uri.parse('https://example.org');
        final session = CallSession.forIncoming(
          room: room,
          callId: 'call-wiring',
          kind: CallKind.voice,
          callsHttpClient: module,
        );
        addTearDown(session.dispose);

        await expectLater(session.accept(), throwsA(anything));

        expect(turnAnsweredAfterSession, isTrue);
        expect(requests.map((r) => r.url.path).toSet(), {
          '$base/turn/credentials',
          '$base/sessions/new',
        });
        expect(requests.map((r) => r.headers['Authorization']).toSet(), {
          'Bearer test-token',
        });
        expect(
          requests
              .where((r) => r.url.path == '$base/turn/credentials')
              .single
              .body,
          isEmpty,
        );
      },
    );
  });
}

class _OrderTrackingCallEngine implements CallEngine {
  _OrderTrackingCallEngine(this.calls);

  final List<String> calls;

  @override
  CallEngineStatus get status => CallEngineStatus.connected;
  @override
  Stream<CallEngineStatus> get statusStream => const Stream.empty();

  @override
  List<CallEngineParticipant> get participants => const [];
  @override
  Stream<List<CallEngineParticipant>> get participantsStream =>
      const Stream.empty();

  @override
  CallKind get kind => CallKind.voice;

  @override
  Future<void> join() async {
    calls.add('join');
  }

  @override
  Future<void> leave() async {}

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> switchToVideo() async {}

  @override
  Map<String, Object?>? get localFociInfo => const {
    'sessionId': 'fake-session',
    'tracks': {'audio': 'audio'},
  };

  @override
  void updateRemoteParticipant(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
  ) {}
  @override
  void removeRemoteParticipant(VoipParticipantId id) {}

  @override
  Future<void> setEncryptionKey(Uint8List key) async {
    calls.add('setEncryptionKey');
  }

  @override
  CallQuality get quality => CallQuality.good;
  @override
  Stream<void> get localStateChangedStream => const Stream.empty();

  @override
  void dispose() {}
}
