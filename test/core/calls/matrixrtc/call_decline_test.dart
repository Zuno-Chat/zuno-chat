import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('a decline that has to reach the server', () {
    Room roomAnswering(int status) {
      final client = buildTestClient(
        userId: '@me:x',
        database: SendCapableFakeDatabaseApi(),
        httpClient: MockClient(
          (request) async => status == 200
              ? http.Response(jsonEncode({'event_id': r'$decline'}), 200)
              : http.Response('{"errcode":"M_UNKNOWN"}', status),
        ),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      final room = buildTestRoom(client);
      client.rooms.add(room);
      return room;
    }

    test('one call is always declined under one transaction id, so a second '
        'decline from this device is not a second event', () async {
      final paths = <String>[];
      final client = buildTestClient(
        userId: '@me:x',
        database: SendCapableFakeDatabaseApi(),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(jsonEncode({'event_id': r'$decline'}), 200);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      final room = buildTestRoom(client);
      client.rooms.add(room);

      await declineCall(room, 'c1');
      await declineCallOrFail(room, 'c1');

      expect(paths, hasLength(2));
      expect(paths.first, paths.last);
      expect(paths.first, endsWith('/${callDeclineTxid('c1')}'));
    });

    test('completes once the server has it', () async {
      await expectLater(declineCallOrFail(roomAnswering(200), 'c1'), completes);
    });

    test(
      'fails when the server refused it, so it can be tried again',
      () async {
        await expectLater(
          declineCallOrFail(roomAnswering(500), 'c1'),
          throwsA(isA<CallDeclineNotSent>()),
        );
      },
    );
  });
}
