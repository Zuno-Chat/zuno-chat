import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

class _FakeStream extends MediaStream {
  _FakeStream(String id) : super(id, 'test');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const id = VoipParticipantId(userId: '@a:x', deviceId: 'D1');

  test('copyWith updates only the given fields', () {
    const original = CallEngineParticipant(
      id: id,
      isLocal: true,
      audioMuted: false,
    );
    final updated = original.copyWith(audioMuted: true);
    expect(updated.audioMuted, isTrue);
    expect(updated.isLocal, original.isLocal);
    expect(updated.id, original.id);
  });

  test('unspecified stream fields default to keeping the current value', () {
    const original = CallEngineParticipant(
      id: id,
      isLocal: false,
      videoEnabled: true,
    );
    final updated = original.copyWith(audioMuted: true);
    expect(updated.videoEnabled, isTrue);
  });

  test('clearVideoStream explicitly nulls it out rather than keeping it', () {
    const original = CallEngineParticipant(id: id, isLocal: true);
    final updated = original.copyWith(clearVideoStream: true);
    expect(updated.videoStream, isNull);
  });

  test('copyWith keeps the camera facing unless given', () {
    const original = CallEngineParticipant(
      id: id,
      isLocal: true,
      frontCamera: true,
    );
    expect(original.copyWith(audioMuted: true).frontCamera, isTrue);
    expect(original.copyWith(frontCamera: false).frontCamera, isFalse);
  });

  group('value equality', () {
    const id = VoipParticipantId(userId: '@bob:example.org', deviceId: 'B');

    test('two participants with the same fields are equal', () {
      const a = CallEngineParticipant(id: id, isLocal: false, encrypted: true);
      const b = CallEngineParticipant(id: id, isLocal: false, encrypted: true);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('a changed flag breaks equality', () {
      const a = CallEngineParticipant(id: id, isLocal: false);
      expect(a, isNot(equals(a.copyWith(audioMuted: true))));
      expect(a, isNot(equals(a.copyWith(lowBandwidth: true))));
      expect(a, isNot(equals(a.copyWith(encrypted: true))));
      expect(a, isNot(equals(a.copyWith(frontCamera: true))));
    });

    test('streams compare by id, not identity', () {
      final a = CallEngineParticipant(
        id: id,
        isLocal: false,
        videoStream: _FakeStream('v1'),
      );
      final b = CallEngineParticipant(
        id: id,
        isLocal: false,
        videoStream: _FakeStream('v1'),
      );
      final c = CallEngineParticipant(
        id: id,
        isLocal: false,
        videoStream: _FakeStream('v2'),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
