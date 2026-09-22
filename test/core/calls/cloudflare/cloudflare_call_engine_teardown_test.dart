import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_call_engine.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

final _baseUri = Uri.parse(
  'https://example.org/_synapse/client/zuno/calls/cloudflare',
);

CloudflareCallEngine _buildEngine({CallKind kind = CallKind.voice}) =>
    CloudflareCallEngine(
      baseUri: _baseUri,
      authorization: () async => 'Bearer test-token',
      kind: kind,
    );

void main() {
  const remoteId = VoipParticipantId(userId: '@bob:example.org', deviceId: 'B');
  const remoteFoci = {
    'sessionId': 'remote-session',
    'tracks': {'audio': 'audio'},
  };

  group('happy path', () {
    test('the local participant starts on the front camera', () {
      final engine = _buildEngine(kind: CallKind.video);
      final local = engine.participants.single;
      expect(local.isLocal, isTrue);
      expect(local.frontCamera, isTrue);
    });

    test('leaving reports disconnected and drops every participant', () async {
      final engine = _buildEngine();
      final statuses = <CallEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      engine.updateRemoteParticipant(remoteId, remoteFoci);
      expect(engine.participants, hasLength(2));

      await engine.leave();
      await pumpEventQueue();

      expect(engine.status, CallEngineStatus.disconnected);
      expect(statuses, [CallEngineStatus.disconnected]);
      expect(engine.participants.where((p) => !p.isLocal), isEmpty);
    });

    test('an unchanged membership does not re-emit participants', () async {
      final engine = _buildEngine();
      final emissions = <List<CallEngineParticipant>>[];
      engine.participantsStream.listen(emissions.add);

      engine.updateRemoteParticipant(remoteId, remoteFoci);
      engine.updateRemoteParticipant(remoteId, remoteFoci);
      await pumpEventQueue();

      expect(emissions, hasLength(1));
    });

    test('a changed mute flag re-emits participants', () async {
      final engine = _buildEngine();
      final emissions = <List<CallEngineParticipant>>[];
      engine.participantsStream.listen(emissions.add);

      engine.updateRemoteParticipant(remoteId, remoteFoci);
      engine.updateRemoteParticipant(remoteId, {
        ...remoteFoci,
        'audioMuted': true,
      });
      await pumpEventQueue();

      expect(emissions, hasLength(2));
      expect(emissions.last.last.audioMuted, isTrue);
    });

    test('a membership advertising an encryption key marks the participant encrypted', () async {
      final engine = _buildEngine();

      engine.updateRemoteParticipant(remoteId, {
        ...remoteFoci,
        'encrypted': true,
      });
      await pumpEventQueue();

      final remote = engine.participants.firstWhere((p) => !p.isLocal);
      expect(remote.encrypted, isTrue);
    });

    test(
      'a membership with no key leaves the participant unencrypted',
      () async {
        final engine = _buildEngine();

        engine.updateRemoteParticipant(remoteId, remoteFoci);
        await pumpEventQueue();

        final remote = engine.participants.firstWhere((p) => !p.isLocal);
        expect(remote.encrypted, isFalse);
      },
    );
  });

  group('sad paths', () {
    test('leaving after dispose does not throw', () async {
      final engine = _buildEngine();
      engine.dispose();
      await pumpEventQueue();

      await expectLater(engine.leave(), completes);
    });

    test('leaving twice tears down once and reports once', () async {
      final engine = _buildEngine();
      final statuses = <CallEngineStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.leave();
      await expectLater(engine.leave(), completes);
      await pumpEventQueue();

      expect(statuses, [CallEngineStatus.disconnected]);
    });

    test(
      'disposing while participants are still held does not throw',
      () async {
        final engine = _buildEngine();
        engine.updateRemoteParticipant(remoteId, remoteFoci);

        engine.dispose();
        await pumpEventQueue();

        expect(engine.status, CallEngineStatus.disconnected);
      },
    );

    test('a membership arriving after teardown does not re-join', () async {
      final engine = _buildEngine();
      await engine.leave();
      engine.dispose();
      await pumpEventQueue();

      engine.updateRemoteParticipant(remoteId, remoteFoci);
      await pumpEventQueue();

      expect(engine.participants.where((p) => !p.isLocal), isEmpty);
    });

    test('a departure arriving after teardown is a no-op', () async {
      final engine = _buildEngine();
      engine.updateRemoteParticipant(remoteId, remoteFoci);
      await engine.leave();
      engine.dispose();
      await pumpEventQueue();

      engine.removeRemoteParticipant(remoteId);
      await pumpEventQueue();

      expect(engine.participants.where((p) => !p.isLocal), isEmpty);
    });
  });
}
