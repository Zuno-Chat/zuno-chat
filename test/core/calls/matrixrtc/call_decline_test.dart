import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_decline.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';

import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/send_recording_room.dart';

void main() {
  late Room room;

  setUp(() {
    final client = buildTestClient(userId: '@me:x');
    room = buildTestRoom(client);
  });

  test('references the caller\'s membership so the decline does not push', () {
    joinCall(room, userId: '@caller:x', deviceId: 'DEV', callId: 'c1');

    final content = callDeclineContent(room, 'c1');

    expect(content['msgtype'], callDeclineMsgtype);
    expect(content['call_id'], 'c1');
    expect(content['m.relates_to'], {
      'rel_type': 'm.reference',
      'event_id': r'$member-@caller:x-DEV-c1',
    });
  });

  test('ignores your own membership and other calls', () {
    joinCall(room, userId: '@me:x', deviceId: 'DEV', callId: 'c1');
    joinCall(
      room,
      userId: '@caller:x',
      deviceId: 'DEV',
      callId: 'another-call',
    );

    expect(callDeclineContent(room, 'c1'), isNot(contains('m.relates_to')));
  });

  test('still declines when no membership is known', () {
    final content = callDeclineContent(room, 'c1');

    expect(content['msgtype'], callDeclineMsgtype);
    expect(content, isNot(contains('m.relates_to')));
  });

  test(
    'keeps no local copy that could be resent once the call is over',
    () async {
      final recording = SendRecordingRoom(
        client: buildTestClient(userId: '@me:x'),
      );

      await declineCall(recording, 'c1');
      await declineCallOrFail(recording, 'c1');

      expect(recording.pendingCopies, [false, false]);
    },
  );

  group('a decline that has to reach the server', () {
    late List<String> paths;

    Room roomAnswering(int status) {
      final client = buildTestClient(
        userId: '@me:x',
        database: SendCapableFakeDatabaseApi(),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return status == 200
              ? http.Response(jsonEncode({'event_id': r'$decline'}), 200)
              : http.Response('{"errcode":"M_UNKNOWN"}', status);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      final room = buildTestRoom(client);
      client.rooms.add(room);
      return room;
    }

    setUp(() => paths = []);

    test('one call is always declined under one transaction id, so a second '
        'decline from this device is not a second event', () async {
      final room = roomAnswering(200);

      await declineCall(room, 'c1');
      await declineCallOrFail(room, 'c1');

      expect(paths, hasLength(2));
      expect(paths.first, paths.last);
      expect(paths.first, endsWith('/${callDeclineTxid('c1')}'));
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
