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
  const id = VoipParticipantId(userId: '@bob:example.org', deviceId: 'B');

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
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
  });
}
