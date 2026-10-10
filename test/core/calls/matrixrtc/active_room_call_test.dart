import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/active_room_call.dart';

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
    int createdAtMs = 0,
  }) => joinCall(
    room,
    userId: userId,
    deviceId: 'DEVICE',
    callId: callId,
    kind: kind,
    createdAtMs: createdAtMs,
  );

  group('call capacity', () {
    void fill(int count, {String callId = 'c1'}) {
      for (var i = 0; i < count; i++) {
        publishMembership('@p$i:x', callId: callId, createdAtMs: i);
      }
    }

    test('a call with 6 other people is full', () {
      fill(6);
      expect(isCallFull(room, 'c1', excludeUserId: '@me:x'), isTrue);
    });

    test('a call with 5 other people has room', () {
      fill(5);
      expect(isCallFull(room, 'c1', excludeUserId: '@me:x'), isFalse);
    });

    test('my own membership never takes the last place', () {
      fill(5);
      publishMembership('@me:x', callId: 'c1');
      expect(isCallFull(room, 'c1', excludeUserId: '@me:x'), isFalse);
    });

    test('people in a different call do not count', () {
      fill(5);
      publishMembership('@other:x', callId: 'c2');
      expect(isCallFull(room, 'c1', excludeUserId: '@me:x'), isFalse);
    });

    test('someone who joined after the first 6 is over capacity', () {
      fill(6);
      publishMembership('@me:x', callId: 'c1', createdAtMs: 100);
      expect(isOverCallCapacity(room, 'c1', '@me:x'), isTrue);
      expect(isOverCallCapacity(room, 'c1', '@p5:x'), isFalse);
    });

    test('an earlier join keeps its place even when 7 are in', () {
      fill(6);
      publishMembership('@me:x', callId: 'c1', createdAtMs: -1);
      expect(isOverCallCapacity(room, 'c1', '@me:x'), isFalse);
      expect(isOverCallCapacity(room, 'c1', '@p5:x'), isTrue);
    });

    test('a join-time tie is broken by user id', () {
      for (final id in [
        '@a:x',
        '@b:x',
        '@c:x',
        '@d:x',
        '@e:x',
        '@f:x',
        '@g:x',
      ]) {
        publishMembership(id, callId: 'c1', createdAtMs: 5);
      }
      expect(isOverCallCapacity(room, 'c1', '@g:x'), isTrue);
      expect(isOverCallCapacity(room, 'c1', '@f:x'), isFalse);
    });

    test('someone not in the call is never over capacity', () {
      fill(7);
      expect(isOverCallCapacity(room, 'c1', '@me:x'), isFalse);
    });
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
