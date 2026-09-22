import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';

import '../../../helpers/fake_matrix.dart';

Map<String, Object?> _membershipJson({
  String callId = 'call1',
  String deviceId = 'device1',
  String kind = 'voice',
  required int expiresAtMs,
}) => {
  'call_id': callId,
  'device_id': deviceId,
  'kind': kind,
  'expires_ts': expiresAtMs,
  'foci_active': <String, Object?>{},
};

void main() {
  test('parses non-expired memberships', () {
    final future = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final memberships = parseRtcMemberships({
      'memberships': [_membershipJson(expiresAtMs: future)],
    });
    expect(memberships, hasLength(1));
    expect(memberships.single.callId, 'call1');
  });

  test('filters out an expired membership', () {
    final past = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final memberships = parseRtcMemberships({
      'memberships': [_membershipJson(expiresAtMs: past)],
    });
    expect(memberships, isEmpty);
  });

  test('null/missing content is treated as no memberships', () {
    expect(parseRtcMemberships(null), isEmpty);
    expect(parseRtcMemberships({}), isEmpty);
  });

  test('a non-list "memberships" value is treated as no memberships', () {
    expect(parseRtcMemberships({'memberships': 'not a list'}), isEmpty);
  });

  test('toJson/fromJson round-trips', () {
    final future = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final original = RtcMembership.fromJson(
      _membershipJson(expiresAtMs: future),
    );
    final roundTripped = RtcMembership.fromJson(original.toJson());
    expect(roundTripped.callId, original.callId);
    expect(roundTripped.deviceId, original.deviceId);
    expect(roundTripped.expiresAtMs, original.expiresAtMs);
  });

  test('the join time round-trips', () {
    final future = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final membership = RtcMembership.fromJson({
      ..._membershipJson(expiresAtMs: future),
      'created_ts': 1234,
    });
    expect(RtcMembership.fromJson(membership.toJson()).createdAtMs, 1234);
  });

  test('a membership without a join time reads as the earliest join', () {
    final future = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    expect(
      RtcMembership.fromJson(_membershipJson(expiresAtMs: future)).createdAtMs,
      0,
    );
  });

  group('canPublishCallMemberState', () {
    void setPowerLevels(Room room, Map<String, Object?> content) {
      room.setState(
        buildTestEvent(
          room,
          eventId: '\$powerlevels',
          senderId: '@creator:example.org',
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          content: content,
        ),
      );
    }

    test(
      'allows a plain member when the room has no power_levels event at all',
      () {
        final client = buildTestClient(userId: '@alice:example.org');
        final room = buildTestRoom(client);
        expect(canPublishCallMemberState(room), isTrue);
      },
    );

    test(
      'denies a plain member in a room requiring moderator to send state',
      () {
        final client = buildTestClient(userId: '@member:example.org');
        final room = buildTestRoom(client);
        setPowerLevels(room, {'state_default': 50, 'users_default': 0});
        expect(canPublishCallMemberState(room), isFalse);
      },
    );

    test('allows a member whose own power level meets state_default', () {
      final client = buildTestClient(userId: '@mod:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'state_default': 50,
        'users': {'@mod:example.org': 50},
      });
      expect(canPublishCallMemberState(room), isTrue);
    });

    test(
      'an explicit events override for this event type wins over state_default',
      () {
        final client = buildTestClient(userId: '@alice:example.org');
        final room = buildTestRoom(client);
        setPowerLevels(room, {
          'state_default': 50,
          'events': {callMemberEventType: 0},
        });
        expect(canPublishCallMemberState(room), isTrue);
      },
    );
  });

  group('hasSomeoneToCall', () {
    Room roomWith({int? joined, List<String> joinedIds = const []}) {
      final client = buildTestClient(userId: '@alice:example.org');
      final room = buildTestRoom(client);
      if (joined != null) {
        room.summary = RoomSummary.fromJson({'m.joined_member_count': joined});
      }
      for (final id in joinedIds) {
        room.setState(
          Event(
            eventId: '\$member-$id',
            type: EventTypes.RoomMember,
            stateKey: id,
            senderId: id,
            originServerTs: DateTime.now(),
            content: const {'membership': 'join'},
            room: room,
          ),
        );
      }
      return room;
    }

    test('a chat somebody else has joined can be called', () {
      expect(hasSomeoneToCall(roomWith(joined: 2)), isTrue);
    });

    test('an invitation nobody has accepted yet cannot', () {
      expect(hasSomeoneToCall(roomWith(joined: 1)), isFalse);
    });

    test('a group everyone else has left cannot', () {
      expect(hasSomeoneToCall(roomWith(joined: 1)), isFalse);
    });

    test('falls back to member state when the summary has no count', () {
      expect(
        hasSomeoneToCall(roomWith(joinedIds: ['@alice:example.org'])),
        isFalse,
      );
      expect(
        hasSomeoneToCall(
          roomWith(joinedIds: ['@alice:example.org', '@bob:example.org']),
        ),
        isTrue,
      );
    });

    test('the summary wins over member state that has not loaded', () {
      final room = roomWith(joined: 2);
      expect(room.getParticipants([Membership.join]), isEmpty);
      expect(hasSomeoneToCall(room), isTrue);
    });
  });
}
