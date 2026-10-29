import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';

import '../../../helpers/call_membership.dart';
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
    final future = clock
        .now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final memberships = parseRtcMemberships({
      'memberships': [_membershipJson(expiresAtMs: future)],
    });
    expect(memberships, hasLength(1));
    expect(memberships.single.callId, 'call1');
  });

  test('filters out an expired membership', () {
    final past = clock
        .now()
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

  test('an entry of the wrong shape is skipped and the rest are kept', () {
    final future = clock
        .now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final memberships = parseRtcMemberships({
      'memberships': [
        <String, Object?>{},
        'junk',
        {
          'application': 'm.call',
          'call_id': '',
          'scope': 'm.room',
          'device_id': 'ELEMENT',
          'expires': 3600000,
          'expires_ts': future,
          'foci_active': [
            {'type': 'livekit', 'livekit_service_url': 'https://lk'},
          ],
        },
        {..._membershipJson(expiresAtMs: future), 'call_id': 3},
        {..._membershipJson(expiresAtMs: future), 'kind': null},
        {..._membershipJson(expiresAtMs: future), 'expires_ts': '1'},
        {..._membershipJson(expiresAtMs: future), 'created_ts': 'early'},
        {..._membershipJson(expiresAtMs: future), 'foci_active': []},
        _membershipJson(callId: 'good', expiresAtMs: future),
      ],
    });

    expect(memberships.map((m) => m.callId), ['good']);
  });

  test('expired memberships are kept only when asked for', () {
    final content = {
      'memberships': [_membershipJson(expiresAtMs: 1)],
    };

    expect(parseRtcMemberships(content), isEmpty);
    expect(
      parseRtcMemberships(content, includeExpired: true).single.callId,
      'call1',
    );
  });

  test('toJson and parsing round-trip every field', () {
    final future = clock
        .now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final original = RtcMembership.tryParse({
      ..._membershipJson(kind: 'video', expiresAtMs: future),
      'created_ts': 1234,
      'foci_active': {'sessionId': 's1'},
    })!;

    final roundTripped = RtcMembership.tryParse(original.toJson())!;

    expect(roundTripped.callId, 'call1');
    expect(roundTripped.deviceId, 'device1');
    expect(roundTripped.kind, 'video');
    expect(roundTripped.expiresAtMs, future);
    expect(roundTripped.createdAtMs, 1234);
    expect(roundTripped.fociActive, {'sessionId': 's1'});
  });

  test('a membership without a join time reads as the earliest join', () {
    final future = clock
        .now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    expect(
      RtcMembership.tryParse(_membershipJson(expiresAtMs: future))?.createdAtMs,
      0,
    );
  });

  group('answered on another device', () {
    late Room room;

    setUp(() {
      room = buildTestRoom(
        buildTestClient(userId: '@me:example.org', deviceId: 'THISPHONE'),
      );
    });

    test('is true once my membership on another device joins the call', () {
      joinCall(room, userId: '@me:example.org', deviceId: 'LAPTOP');

      expect(answeredOnAnotherDevice(room, 'c1'), isTrue);
    });

    test('is false for my membership on this device', () {
      joinCall(room, userId: '@me:example.org', deviceId: 'THISPHONE');

      expect(answeredOnAnotherDevice(room, 'c1'), isFalse);
    });

    test('is false when my other device is in a different call', () {
      joinCall(
        room,
        userId: '@me:example.org',
        deviceId: 'LAPTOP',
        callId: 'c2',
      );

      expect(answeredOnAnotherDevice(room, 'c1'), isFalse);
    });

    test('is false when someone else joins, as the caller does', () {
      joinCall(room, userId: '@bob:example.org', deviceId: 'LAPTOP');

      expect(answeredOnAnotherDevice(room, 'c1'), isFalse);
    });

    test('is false with no call membership at all', () {
      expect(answeredOnAnotherDevice(room, 'c1'), isFalse);
    });
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
      'denies a plain member in a room requiring moderator to send state',
      () {
        final client = buildTestClient(userId: '@member:example.org');
        final room = buildTestRoom(client);
        setPowerLevels(room, {'state_default': 50, 'users_default': 0});
        expect(canPublishCallMemberState(room), isFalse);
      },
    );

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
            originServerTs: clock.now(),
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

    test('a chat nobody else is in cannot, whether the invitation is still '
        'pending or everyone else left', () {
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

  group('canStartCall', () {
    Room roomWith({required int joined, required int stateDefault}) {
      final room = buildTestRoom(buildTestClient(userId: '@alice:example.org'));
      room.summary = RoomSummary.fromJson({'m.joined_member_count': joined});
      setPowerLevels(room, {'state_default': stateDefault, 'users_default': 0});
      return room;
    }

    test('needs both the right to join a call and somebody to call', () {
      expect(canStartCall(roomWith(joined: 2, stateDefault: 0)), isTrue);
      expect(canStartCall(roomWith(joined: 1, stateDefault: 0)), isFalse);
      expect(canStartCall(roomWith(joined: 2, stateDefault: 50)), isFalse);
    });
  });
}
