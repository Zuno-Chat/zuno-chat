import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/voip_participant_id.dart';

void main() {
  test('equal when userId and deviceId both match', () {
    const a = VoipParticipantId(userId: '@a:x', deviceId: 'D1');
    const b = VoipParticipantId(userId: '@a:x', deviceId: 'D1');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('not equal when the device differs (same user, two devices)', () {
    const a = VoipParticipantId(userId: '@a:x', deviceId: 'D1');
    const b = VoipParticipantId(userId: '@a:x', deviceId: 'D2');
    expect(a, isNot(b));
  });

  test('not equal when the user differs', () {
    const a = VoipParticipantId(userId: '@a:x', deviceId: 'D1');
    const b = VoipParticipantId(userId: '@b:x', deviceId: 'D1');
    expect(a, isNot(b));
  });

  test('usable as a Set/Map key', () {
    final ids = [
      VoipParticipantId(userId: '@a:x', deviceId: 'D1'),
      VoipParticipantId(userId: '@a:x', deviceId: 'D1'),
    ];
    expect(ids.toSet(), hasLength(1));
  });
}
