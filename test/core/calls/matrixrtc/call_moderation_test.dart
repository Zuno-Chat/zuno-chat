import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/matrixrtc/call_moderation.dart';
import 'package:zuno/core/calls/module/calls_module.dart';

import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/send_recording_room.dart';

const _me = '@me:example.org';
const _mod = '@mod:example.org';
const _bob = '@bob:example.org';

Client _moduleClient() => buildTestClient(userId: _me, deviceId: 'MEDEV')
  ..homeserver = Uri.parse('https://example.org')
  ..accessToken = 'syt_token';

void main() {
  group('callModerationGate', () {
    test('offers it in a room to someone who can remove people', () {
      final room = buildTestRoom(buildTestClient(userId: _me));
      setPowerLevels(room, {
        'users': {_me: 50},
      });

      expect(callModerationGate(room)(_bob), isTrue);
    });

    test('never offers it in a chat, whatever the roles', () {
      final client = buildTestClient(userId: _me);
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {_me: 100},
      });
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          _bob: [room.id],
        },
      );

      expect(callModerationGate(room)(_bob), isFalse);
    });

    test('never offers it to someone it would not apply to', () {
      final room = buildTestRoom(buildTestClient(userId: _me));

      expect(callModerationGate(room)(_bob), isFalse);
    });
  });

  group('CallModeration.fromEvent', () {
    late Room room;

    setUp(() => room = buildTestRoom(buildTestClient(userId: _me)));

    Event event(String type, Map<String, Object?> content) => buildTestEvent(
      room,
      eventId: r'$moderation',
      senderId: _mod,
      type: type,
      content: content,
    );

    test('reads a mute aimed at one join of one person in one call', () {
      final mute = CallModeration.fromEvent(
        event(callMuteEventType, {
          'call_id': 'call1',
          'user_id': _bob,
          'membership_created_ts': 1234,
        }),
      );

      expect(
        mute,
        isA<CallMute>()
            .having((m) => m.callId, 'callId', 'call1')
            .having((m) => m.userId, 'userId', _bob)
            .having((m) => m.membershipCreatedTs, 'joined at', 1234),
      );
    });

    test('reads a removal of one person from one call', () {
      final removal = CallModeration.fromEvent(
        event(callRemoveEventType, {'call_id': 'call1', 'user_id': _bob}),
      );

      expect(
        removal,
        isA<CallRemoval>()
            .having((m) => m.callId, 'callId', 'call1')
            .having((m) => m.userId, 'userId', _bob),
      );
    });

    for (final (reason, type, content)
        in <(String, String, Map<String, Object?>)>[
          (
            'a mute naming no join',
            callMuteEventType,
            {'call_id': 'c', 'user_id': _bob},
          ),
          (
            'a mute whose join is not a number',
            callMuteEventType,
            {'call_id': 'c', 'user_id': _bob, 'membership_created_ts': '1'},
          ),
          ('a removal naming nobody', callRemoveEventType, {'call_id': 'c'}),
          ('a removal naming no call', callRemoveEventType, {'user_id': _bob}),
          (
            'any other event',
            EventTypes.Message,
            {'call_id': 'c', 'user_id': _bob},
          ),
        ]) {
      test('ignores $reason', () {
        expect(CallModeration.fromEvent(event(type, content)), isNull);
      });
    }
  });

  group('muteInCall', () {
    late SendRecordingRoom room;

    setUp(() => room = SendRecordingRoom(client: buildTestClient(userId: _me)));

    test('asks that one join to mute, off the push path and with no local '
        'copy', () async {
      joinCall(
        room,
        userId: _bob,
        deviceId: 'BOB',
        callId: 'call1',
        createdAtMs: 77,
      );

      await muteInCall(room, callId: 'call1', userId: _bob);

      expect(room.requests.single.type, callMuteEventType);
      expect(room.sentEvents.single, {
        'call_id': 'call1',
        'user_id': _bob,
        'membership_created_ts': 77,
        'm.relates_to': {
          'rel_type': 'm.reference',
          'event_id': r'$member-@bob:example.org-BOB-call1',
        },
      });
      expect(room.pendingCopies, [false]);
    });

    test('sends nothing once they have left the call', () async {
      joinCall(room, userId: _bob, deviceId: 'BOB', callId: 'another-call');

      await muteInCall(room, callId: 'call1', userId: _bob);

      expect(room.attempts, isEmpty);
    });

    test('fails when the request is not sent', () async {
      joinCall(room, userId: _bob, deviceId: 'BOB', callId: 'call1');
      room.undelivered = true;

      await expectLater(
        muteInCall(room, callId: 'call1', userId: _bob),
        throwsA(isA<CallModerationNotSent>()),
      );
    });
  });

  group('removeFromCall', () {
    late SendRecordingRoom room;
    late List<http.Request> moduleRequests;
    late http.Response moduleAnswer;

    setUp(() {
      room = SendRecordingRoom(client: _moduleClient());
      moduleRequests = [];
      moduleAnswer = http.Response('{}', 200);
    });

    Future<void> remove() => removeFromCall(
      room,
      callId: 'call1',
      userId: _bob,
      httpClient: MockClient((request) async {
        moduleRequests.add(request);
        return moduleAnswer;
      }),
    );

    test('has the server cut them off first, then tells the call, off the '
        'push path, once', () async {
      joinCall(room, userId: _bob, deviceId: 'BOB', callId: 'call1');

      await remove();

      expect(
        moduleRequests.single.url.path,
        '/_synapse/client/zuno/calls/remove',
      );
      expect(jsonDecode(moduleRequests.single.body), {'user_id': _bob});
      expect(room.requests.single.type, callRemoveEventType);
      expect(room.sentEvents.single, {
        'call_id': 'call1',
        'user_id': _bob,
        'm.relates_to': {
          'rel_type': 'm.reference',
          'event_id': r'$member-@bob:example.org-BOB-call1',
        },
      });
      expect(room.requests.single.txid, 'zuno-remove-call1-@bob:example.org');
      expect(room.pendingCopies, [false]);
    });

    test('tells the call nothing when the server refuses', () async {
      joinCall(room, userId: _bob, deviceId: 'BOB', callId: 'call1');
      moduleAnswer = http.Response('{"errcode":"M_FORBIDDEN"}', 403);

      await expectLater(remove(), throwsA(isA<CallsModuleException>()));
      expect(room.attempts, isEmpty);
    });

    test('still has the server keep out someone who already left', () async {
      await remove();

      expect(moduleRequests, hasLength(1));
      expect(room.attempts, isEmpty);
    });

    test('a removal the server made stands even when the call cannot be '
        'told', () async {
      joinCall(room, userId: _bob, deviceId: 'BOB', callId: 'call1');
      room.undelivered = true;

      await expectLater(remove(), completes);
      expect(moduleRequests, hasLength(1));
    });
  });
}
