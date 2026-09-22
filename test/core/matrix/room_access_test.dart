import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_access.dart';
import 'package:zuno/core/matrix/room_permission.dart';
import 'package:zuno/core/matrix/room_roles.dart';

import '../../helpers/fake_matrix.dart';

void setJoinRule(Room room, String rule) => room.setState(
  buildTestEvent(
    room,
    eventId: r'$join',
    senderId: '@creator:example.org',
    type: EventTypes.RoomJoinRules,
    stateKey: '',
    content: {'join_rule': rule},
  ),
);

void setPowerLevels(Room room, Map<String, Object?> content) => room.setState(
  buildTestEvent(
    room,
    eventId: r'$powerlevels',
    senderId: '@creator:example.org',
    type: EventTypes.RoomPowerLevels,
    stateKey: '',
    content: content,
  ),
);

void main() {
  group('roomAccessOf', () {
    test('reads a public join rule as public', () {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
      setJoinRule(room, 'public');

      expect(roomAccessOf(room), RoomAccess.public);
    });

    test('reads an invite join rule as private', () {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
      setJoinRule(room, 'invite');

      expect(roomAccessOf(room), RoomAccess.private);
    });

    test('treats a missing join rule as private', () {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));

      expect(roomAccessOf(room), RoomAccess.private);
    });
  });

  group('canChangeRoomAccess', () {
    test('admins of a group can', () {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
      setPowerLevels(room, {
        'users': {'@me:example.org': 100},
      });

      expect(canChangeRoomAccess(room), isTrue);
    });

    test('moderators cannot', () {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
      setPowerLevels(room, {
        'users': {'@me:example.org': 50},
      });

      expect(canChangeRoomAccess(room), isFalse);
    });

    test('nobody can in a direct chat', () {
      final client = buildTestClient(userId: '@me:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@me:example.org': 100},
      });
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [room.id],
        },
      );

      expect(canChangeRoomAccess(room), isFalse);
    });
  });

  group('setRoomAccess', () {
    late List<http.Request> requests;
    late Room room;
    http.Response? listingResponse;

    setUp(() {
      requests = [];
      listingResponse = null;
      final client = buildTestClient(
        userId: '@me:example.org',
        httpClient: MockClient((request) async {
          requests.add(request);
          final refusal = listingResponse;
          if (refusal != null &&
              request.url.pathSegments.contains('directory')) {
            return refusal;
          }
          return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      room = buildTestRoom(client);
    });

    test('public lists the room, then sets the join rule', () async {
      await setRoomAccess(room, RoomAccess.public);

      expect(requests, hasLength(2));
      expect(requests[0].url.pathSegments, contains('directory'));
      expect(requests[0].url.pathSegments.last, '!room:example.org');
      expect(jsonDecode(requests[0].body), {'visibility': 'public'});
      expect(requests[1].url.pathSegments, contains('m.room.join_rules'));
      expect(jsonDecode(requests[1].body), {'join_rule': 'public'});
      expect(roomAccessOf(room), RoomAccess.public);
    });

    test('private sets an invite join rule, then unlists the room', () async {
      setJoinRule(room, 'public');

      await setRoomAccess(room, RoomAccess.private);

      expect(requests[0].url.pathSegments, contains('m.room.join_rules'));
      expect(jsonDecode(requests[0].body), {'join_rule': 'invite'});
      expect(requests[1].url.pathSegments, contains('directory'));
      expect(jsonDecode(requests[1].body), {'visibility': 'private'});
      expect(roomAccessOf(room), RoomAccess.private);
    });

    test(
      'leaves the room private when the server refuses to list it',
      () async {
        listingResponse = http.Response(
          jsonEncode({
            'errcode': 'M_UNKNOWN',
            'error': 'Not allowed to publish room',
          }),
          403,
        );

        await expectLater(
          setRoomAccess(room, RoomAccess.public),
          throwsA(isA<RoomListingRefused>()),
        );

        expect(requests, hasLength(1));
        expect(roomAccessOf(room), RoomAccess.private);
        expect(
          RoomListingRefused().toString(),
          'Public rooms cannot be listed here',
        );
      },
    );

    test('passes other listing errors through unchanged', () async {
      listingResponse = http.Response(
        jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'Internal error'}),
        500,
      );

      await expectLater(
        setRoomAccess(room, RoomAccess.public),
        throwsA(isA<MatrixException>()),
      );

      expect(roomAccessOf(room), RoomAccess.private);
    });
  });

  group('createGroupRoom', () {
    late List<http.Request> requests;
    late Client client;
    http.Response? createResponse;

    Map<String, Object?> createBody() =>
        jsonDecode(requests.single.body) as Map<String, Object?>;

    Object? callsLevel(Map<String, Object?> body) =>
        ((body['power_level_content_override'] as Map)['events']
            as Map)['m.call.member'];

    setUp(() {
      requests = [];
      createResponse = null;
      client = buildTestClient(
        userId: '@me:example.org',
        httpClient: MockClient((request) async {
          requests.add(request);
          return createResponse ??
              http.Response(jsonEncode({'room_id': '!new:example.org'}), 200);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      client.rooms.add(buildTestRoom(client, id: '!new:example.org'));
    });

    test('private creates an unlisted, invite-only, encrypted room', () async {
      final roomId = await createGroupRoom(
        client,
        name: 'Book club',
        access: RoomAccess.private,
      );

      expect(roomId, '!new:example.org');
      expect(requests.single.url.pathSegments.last, 'createRoom');
      final body = createBody();
      expect(body['name'], 'Book club');
      expect(body['preset'], 'private_chat');
      expect(body.containsKey('visibility'), isFalse);
      expect(
        (body['initial_state'] as List).map((s) => (s as Map)['type']),
        contains(EventTypes.Encryption),
      );
      expect(body['power_level_content_override'], defaultGroupPowerLevels());
      expect(callsLevel(body), RoomRole.member.powerLevel);
    });

    test(
      'public creates a listed, open room that is still encrypted',
      () async {
        await createGroupRoom(
          client,
          name: 'Chess club',
          access: RoomAccess.public,
        );

        final body = createBody();
        expect(body['preset'], 'public_chat');
        expect(body['visibility'], 'public');
        expect(
          (body['initial_state'] as List).map((s) => (s as Map)['type']),
          contains(EventTypes.Encryption),
        );
        expect(
          body['power_level_content_override'],
          defaultGroupPowerLevels(public: true),
        );
        expect(callsLevel(body), RoomRole.moderator.powerLevel);
      },
    );

    test('a server that refuses to list rooms creates nothing and says '
        'so', () async {
      createResponse = http.Response(
        jsonEncode({
          'errcode': 'M_FORBIDDEN',
          'error': 'Not allowed to publish room',
        }),
        403,
      );

      await expectLater(
        createGroupRoom(client, name: 'Chess club', access: RoomAccess.public),
        throwsA(isA<RoomListingRefused>()),
      );
      expect(requests, hasLength(1));
    });

    test('passes other create errors through unchanged', () async {
      createResponse = http.Response(
        jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'Internal error'}),
        500,
      );

      await expectLater(
        createGroupRoom(client, name: 'Chess club', access: RoomAccess.public),
        throwsA(isA<MatrixException>()),
      );
    });
  });

  test('each access says who can get in', () {
    expect(RoomAccess.private.description, 'Invite only');
    expect(RoomAccess.public.description, 'Anyone can find and join');
  });
}
