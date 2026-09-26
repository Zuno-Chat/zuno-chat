import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_decline.dart';
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    final client = buildTestClient(userId: '@me:x');
    room = buildTestRoom(client);
  });

  void publishMembership(String userId, String callId, {String? eventId}) {
    room.setState(
      buildTestEvent(
        room,
        eventId: eventId ?? '\$member-$userId',
        senderId: userId,
        type: callMemberEventType,
        stateKey: userId,
        content: {
          'memberships': [
            RtcMembership(
              callId: callId,
              deviceId: 'DEV',
              kind: 'voice',
              expiresAtMs: DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
              fociActive: const {},
            ).toJson(),
          ],
        },
      ),
    );
  }

  test('references the caller\'s membership so the decline does not push', () {
    publishMembership('@caller:x', 'c1', eventId: r'$caller');

    final content = callDeclineContent(room, 'c1');

    expect(content['msgtype'], callDeclineMsgtype);
    expect(content['call_id'], 'c1');
    expect(content['m.relates_to'], {
      'rel_type': 'm.reference',
      'event_id': r'$caller',
    });
  });

  test('ignores your own membership and other calls', () {
    publishMembership('@me:x', 'c1');
    publishMembership('@caller:x', 'another-call');

    expect(callDeclineContent(room, 'c1'), isNot(contains('m.relates_to')));
  });

  test('still declines when no membership is known', () {
    final content = callDeclineContent(room, 'c1');

    expect(content['msgtype'], callDeclineMsgtype);
    expect(content, isNot(contains('m.relates_to')));
  });
}
