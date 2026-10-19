import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/active_room_call.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';

import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:x');
    room = buildTestRoom(client);
  });

  void publishMembership(
    String userId, {
    required String callId,
    String kind = 'voice',
  }) => joinCall(
    room,
    userId: userId,
    deviceId: 'DEVICE',
    callId: callId,
    kind: kind,
  );

  test('a malformed membership in the room is passed over, not thrown on', () {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$broken',
        senderId: '@broken:x',
        type: callMemberEventType,
        stateKey: '@broken:x',
        content: {
          'memberships': [<String, Object?>{}],
        },
      ),
    );
    publishMembership('@ann:x', callId: 'c1');

    expect(findActiveRoomCall(room, excludeUserId: '@me:x')?.callId, 'c1');
  });

  test('no m.call.member state at all returns null', () {
    expect(findActiveRoomCall(room, excludeUserId: '@me:x'), isNull);
  });

  test('only my own membership returns null — nothing to join', () {
    publishMembership('@me:x', callId: 'c1');
    expect(findActiveRoomCall(room, excludeUserId: '@me:x'), isNull);
  });

  test('another participant\'s membership is surfaced for joining', () {
    publishMembership('@alice:x', callId: 'c1', kind: 'video');
    final call = findActiveRoomCall(room, excludeUserId: '@me:x');
    expect(call?.callId, 'c1');
    expect(call?.kind, 'video');
    expect(call?.participantUserIds, ['@alice:x']);
  });

  test(
    'my own membership is excluded even alongside others\' in the same call',
    () {
      publishMembership('@me:x', callId: 'c1');
      publishMembership('@alice:x', callId: 'c1');
      final call = findActiveRoomCall(room, excludeUserId: '@me:x');
      expect(call!.participantUserIds, ['@alice:x']);
    },
  );

  test(
    'two distinct concurrent calls: the one with more participants wins',
    () {
      publishMembership('@alice:x', callId: 'small');
      publishMembership('@bob:x', callId: 'big');
      publishMembership('@carol:x', callId: 'big');
      final call = findActiveRoomCall(room, excludeUserId: '@me:x');
      expect(call!.callId, 'big');
      expect(call.participantUserIds.toSet(), {'@bob:x', '@carol:x'});
    },
  );
}
