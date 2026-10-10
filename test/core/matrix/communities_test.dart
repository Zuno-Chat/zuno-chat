import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/communities.dart';
import 'package:zuno/core/matrix/room_access.dart';
import 'package:zuno/core/matrix/room_permission.dart';

import '../../helpers/fake_matrix.dart';

const _me = '@me:example.org';

Room addSpace(
  Client client,
  String id, {
  List<String> children = const [],
  Membership membership = Membership.join,
}) {
  final room = buildTestRoom(client, id: id)..membership = membership;
  room.setState(
    buildTestEvent(
      room,
      eventId: '\$create-$id',
      senderId: _me,
      type: EventTypes.RoomCreate,
      stateKey: '',
      content: {'type': 'm.space'},
      originServerTs: DateTime(2026, 1, 1),
    ),
  );
  for (final child in children) {
    room.setState(
      buildTestEvent(
        room,
        eventId: '\$child-$id-$child',
        senderId: _me,
        type: EventTypes.SpaceChild,
        stateKey: child,
        content: {
          'via': ['example.org'],
        },
      ),
    );
  }
  client.rooms.add(room);
  return room;
}

Room addRoom(
  Client client,
  String id, {
  DateTime? at,
  int unread = 0,
  Membership membership = Membership.join,
}) {
  final room = buildTestRoom(client, id: id, notificationCount: unread)
    ..membership = membership;
  if (at != null) {
    room.lastEvent = buildTestEvent(
      room,
      eventId: '\$msg-$id',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'hi'},
      originServerTs: at,
    );
  }
  client.rooms.add(room);
  return room;
}

void makeDirect(Client client, Room room) =>
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@sam:example.org': [room.id],
      },
    );

DateTime at(int hour) => DateTime(2026, 9, 28, hour);

void mute(Client client, Room room) =>
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          'override': [
            {
              'rule_id': room.id,
              'default': false,
              'enabled': true,
              'actions': <Object?>[],
              'conditions': [
                {'kind': 'event_match', 'key': 'room_id', 'pattern': room.id},
              ],
            },
          ],
        },
      },
    );

void main() {
  late Client client;

  setUp(() => client = buildTestClient(userId: _me));

  group('communityRooms', () {
    test('lists the joined rooms of a community, newest first', () {
      final old = addRoom(client, '!old:example.org', at: at(9));
      final recent = addRoom(client, '!recent:example.org', at: at(12));
      final community = addSpace(
        client,
        '!club:example.org',
        children: [old.id, recent.id],
      );

      expect(communityRooms(community), [recent, old]);
    });

    test('leaves out rooms not joined, direct chats and other '
        'communities', () {
      final invited = addRoom(
        client,
        '!invited:example.org',
        membership: Membership.invite,
      );
      final direct = addRoom(client, '!dm:example.org', at: at(10));
      makeDirect(client, direct);
      final nested = addSpace(client, '!nested:example.org');
      final community = addSpace(
        client,
        '!club:example.org',
        children: [invited.id, direct.id, nested.id, '!unknown:example.org'],
      );

      expect(communityRooms(community), isEmpty);
    });
  });

  group('arrangeHome', () {
    test('chats keep their order and leave out communities and their '
        'rooms', () {
      final sam = addRoom(client, '!sam:example.org', at: at(12));
      final gear = addRoom(client, '!gear:example.org', at: at(11));
      final mom = addRoom(client, '!mom:example.org', at: at(10));
      final club = addSpace(client, '!club:example.org', children: [gear.id]);

      final layout = arrangeHome([sam, gear, mom, club]);

      expect(layout.chats, [sam, mom]);
      expect(layout.communities, [club]);
      expect(layout.communityRooms[club.id], [gear]);
    });

    test('communities are ordered by their newest room, or their own '
        'creation without one', () {
      final old = addRoom(client, '!old:example.org', at: at(8));
      final recent = addRoom(client, '!recent:example.org', at: at(12));
      final quiet = addSpace(client, '!quiet:example.org');
      final slow = addSpace(client, '!slow:example.org', children: [old.id]);
      final busy = addSpace(client, '!busy:example.org', children: [recent.id]);

      expect(arrangeHome([old, recent, quiet, slow, busy]).communities, [
        busy,
        slow,
        quiet,
      ]);
    });

    test('invitations are split between the two tabs', () {
      final invitedRoom = addRoom(
        client,
        '!invited:example.org',
        membership: Membership.invite,
      );
      final invitedSpace = addSpace(
        client,
        '!other:example.org',
        membership: Membership.invite,
      );

      final layout = arrangeHome([invitedRoom, invitedSpace]);

      expect(layout.chatInvitations, [invitedRoom]);
      expect(layout.communityInvitations, [invitedSpace]);
      expect(layout.chats, isEmpty);
      expect(layout.communities, isEmpty);
    });

    test('an invitation to a room this person asked to join stays out of '
        'sight while Zuno joins it', () {
      final asked = addRoom(
        client,
        '!asked:example.org',
        membership: Membership.invite,
      );
      final other = addRoom(
        client,
        '!other:example.org',
        membership: Membership.invite,
      );

      final layout = arrangeHome([asked, other], pendingJoins: {asked.id});

      expect(layout.chatInvitations, [other]);
      expect(layout.hasUnreadChats(const {}), isTrue);
    });

    test('a direct chat listed in a community stays in chats', () {
      final direct = addRoom(client, '!dm:example.org', at: at(9));
      makeDirect(client, direct);
      final club = addSpace(client, '!club:example.org', children: [direct.id]);

      final layout = arrangeHome([direct, club]);

      expect(layout.chats, [direct]);
      expect(layout.communityRooms[club.id], isEmpty);
    });

    test('a room in two communities shows under both', () {
      final shared = addRoom(client, '!shared:example.org', at: at(9));
      final a = addSpace(client, '!a:example.org', children: [shared.id]);
      final b = addSpace(client, '!b:example.org', children: [shared.id]);

      final layout = arrangeHome([shared, a, b]);

      expect(layout.chats, isEmpty);
      expect(layout.communityRooms[a.id], [shared]);
      expect(layout.communityRooms[b.id], [shared]);
    });

    group('unread', () {
      test('nothing unread marks neither tab', () {
        final sam = addRoom(client, '!sam:example.org', at: at(9));
        final gear = addRoom(client, '!gear:example.org', at: at(9));
        final club = addSpace(client, '!club:example.org', children: [gear.id]);

        final layout = arrangeHome([sam, gear, club]);

        expect(layout.hasUnreadChats(const {}), isFalse);
        expect(layout.hasUnreadCommunities(const {}), isFalse);
      });

      test('an unread chat marks chats only', () {
        final sam = addRoom(client, '!sam:example.org', at: at(9), unread: 2);

        final layout = arrangeHome([sam]);

        expect(layout.hasUnreadChats(const {}), isTrue);
        expect(layout.hasUnreadCommunities(const {}), isFalse);
      });

      test('an unread room in a community marks communities only', () {
        final gear = addRoom(client, '!gear:example.org', at: at(9), unread: 1);
        final club = addSpace(client, '!club:example.org', children: [gear.id]);

        final layout = arrangeHome([gear, club]);

        expect(layout.hasUnreadChats(const {}), isFalse);
        expect(layout.hasUnreadCommunities(const {}), isTrue);
      });

      test('a call correction that clears the count clears the mark', () {
        final sam = addRoom(client, '!sam:example.org', at: at(9), unread: 1);

        expect(arrangeHome([sam]).hasUnreadChats({sam.id: 1}), isFalse);
      });

      test('a muted room marks nothing', () {
        final sam = addRoom(client, '!sam:example.org', at: at(9), unread: 3);
        mute(client, sam);

        expect(arrangeHome([sam]).hasUnreadChats(const {}), isFalse);
      });

      test('an invitation marks its tab', () {
        final room = addRoom(
          client,
          '!invited:example.org',
          membership: Membership.invite,
        );
        final space = addSpace(
          client,
          '!other:example.org',
          membership: Membership.invite,
        );

        expect(arrangeHome([room]).hasUnreadChats(const {}), isTrue);
        expect(arrangeHome([space]).hasUnreadCommunities(const {}), isTrue);
      });
    });
  });

  group('communitiesOf', () {
    test('names the joined communities that list the room', () {
      final room = addRoom(client, '!gear:example.org');
      final club = addSpace(client, '!club:example.org', children: [room.id]);
      addSpace(client, '!other:example.org');
      addSpace(
        client,
        '!invited:example.org',
        children: [room.id],
        membership: Membership.invite,
      );

      expect(communitiesOf(room), [club]);
    });
  });

  group('communityNameOf', () {
    test('names the community a room belongs to, or nothing', () {
      final room = addRoom(client, '!gear:example.org');
      expect(communityNameOf(room), isNull);

      final club = addSpace(client, '!club:example.org', children: [room.id]);
      club.setState(
        buildTestEvent(
          club,
          eventId: r'$name',
          senderId: _me,
          type: EventTypes.RoomName,
          stateKey: '',
          content: {'name': 'Climbing club'},
        ),
      );

      expect(communityNameOf(room), 'Climbing club');
    });
  });

  group('roomsLeavingWith', () {
    test('takes the rooms no other joined community holds', () {
      final only = addRoom(client, '!only:example.org', at: at(10));
      final shared = addRoom(client, '!shared:example.org', at: at(9));
      final club = addSpace(
        client,
        '!club:example.org',
        children: [only.id, shared.id],
      );
      addSpace(client, '!other:example.org', children: [shared.id]);

      expect(roomsLeavingWith(club), [only]);
    });
  });

  group('server calls', () {
    late List<http.Request> requests;
    http.Response? Function(http.Request)? respond;

    Map<String, Object?> bodyOf(http.Request request) =>
        jsonDecode(request.body) as Map<String, Object?>;

    setUp(() {
      requests = [];
      respond = null;
      client = buildTestClient(
        userId: _me,
        httpClient: MockClient((request) async {
          requests.add(request);
          final custom = respond?.call(request);
          if (custom != null) return custom;
          if (request.url.path.endsWith('/createRoom')) {
            return http.Response(
              jsonEncode({'room_id': '!new:example.org'}),
              200,
            );
          }
          if (request.url.path.contains('/state/')) {
            return http.Response(jsonEncode({'event_id': r'$state'}), 200);
          }
          return http.Response('{}', 200);
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      client.rooms.add(buildTestRoom(client, id: '!new:example.org'));
    });

    test('a private community is an unlisted, invite-only space where only '
        'admins change settings', () async {
      final id = await createCommunity(
        client,
        name: 'Climbing club',
        access: RoomAccess.private,
      );

      expect(id, '!new:example.org');
      final body = bodyOf(requests.single);
      expect(body['name'], 'Climbing club');
      expect(body['creation_content'], {'type': 'm.space'});
      expect(body['preset'], 'private_chat');
      expect(body.containsKey('visibility'), isFalse);
      expect(body.containsKey('initial_state'), isFalse);
      expect(body['power_level_content_override'], communityPowerLevels);
    });

    Future<void> arrive(String id) async {
      await Future<void>.delayed(Duration.zero);
      client.rooms.add(
        buildTestRoom(client, id: id)..membership = Membership.join,
      );
      client.onSync.add(
        SyncUpdate(
          nextBatch: 'next',
          rooms: RoomsUpdate(join: {id: JoinedRoomUpdate()}),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
    }

    test(
      'a new community is only handed back once the sync brings it',
      () async {
        client.rooms.removeWhere((room) => room.id == '!new:example.org');
        var done = false;
        final created = createCommunity(
          client,
          name: 'Club',
          access: RoomAccess.private,
        ).whenComplete(() => done = true);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(done, isFalse);

        await arrive('!new:example.org');

        expect(await created, '!new:example.org');
      },
    );

    test('a new community room is only handed back once the sync brings '
        'it', () async {
      client.rooms.removeWhere((room) => room.id == '!new:example.org');
      final club = addSpace(client, '!club:example.org');
      var done = false;
      final created = createCommunityRoom(
        club,
        name: 'Gear swap',
      ).whenComplete(() => done = true);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isFalse);
      expect(communityChildIds(club), {'!new:example.org'});

      await arrive('!new:example.org');

      expect(await created, '!new:example.org');
    });

    test('a public community is listed and open', () async {
      await createCommunity(
        client,
        name: 'Climbing club',
        access: RoomAccess.public,
      );

      final body = bodyOf(requests.single);
      expect(body['preset'], 'public_chat');
      expect(body['visibility'], 'public');
    });

    test('a server that refuses to list creates no community and says '
        'so', () async {
      respond = (request) => http.Response(
        jsonEncode({
          'errcode': 'M_FORBIDDEN',
          'error': 'Not allowed to publish room',
        }),
        403,
      );

      await expectLater(
        createCommunity(client, name: 'Club', access: RoomAccess.public),
        throwsA(isA<RoomListingRefused>()),
      );
    });

    test('a room made inside a community is encrypted, open to its members '
        'and added to it', () async {
      final club = addSpace(client, '!club:example.org');

      final id = await createCommunityRoom(club, name: 'Gear swap');

      expect(id, '!new:example.org');
      final create = bodyOf(requests.first);
      expect(create['name'], 'Gear swap');
      expect(create['preset'], 'private_chat');
      expect(create['power_level_content_override'], defaultGroupPowerLevels());
      final initial = [
        for (final state in create['initial_state'] as List)
          state as Map<String, Object?>,
      ];
      expect(
        initial.map((s) => s['type']),
        containsAll([
          EventTypes.Encryption,
          EventTypes.RoomJoinRules,
          EventTypes.SpaceParent,
        ]),
      );
      expect(
        initial.firstWhere(
          (s) => s['type'] == EventTypes.RoomJoinRules,
        )['content'],
        {
          'join_rule': 'restricted',
          'allow': [
            {'type': 'm.room_membership', 'room_id': club.id},
          ],
        },
      );
      final parent = initial.firstWhere(
        (s) => s['type'] == EventTypes.SpaceParent,
      );
      expect(parent['state_key'], club.id);

      final link = requests[1];
      expect(link.method, 'PUT');
      expect(
        link.url.path,
        '/_matrix/client/v3/rooms/${Uri.encodeComponent(club.id)}/state/'
        '${EventTypes.SpaceChild}/${Uri.encodeComponent(id)}',
      );
      expect(bodyOf(link), {
        'via': ['example.org'],
      });
      expect(communityChildIds(club), {id});
    });

    for (final (access, rule) in [
      (RoomAccess.askToJoin, {'join_rule': 'knock'}),
      (RoomAccess.private, {'join_rule': 'invite'}),
    ]) {
      test('a ${access.label} room in a community uses ${rule['join_rule']} '
          'and is still added to it', () async {
        final club = addSpace(client, '!club:example.org');

        final id = await createCommunityRoom(
          club,
          name: 'Coaches',
          access: access,
        );

        final create = bodyOf(requests.first);
        final initial = [
          for (final state in create['initial_state'] as List)
            state as Map<String, Object?>,
        ];
        expect(
          initial.firstWhere(
            (s) => s['type'] == EventTypes.RoomJoinRules,
          )['content'],
          rule,
        );
        expect(initial.any((s) => s['type'] == EventTypes.SpaceParent), isTrue);
        expect(communityChildIds(club), {id});
      });
    }

    test('a room that could not be added to its community says so and '
        'keeps its ID', () async {
      final club = addSpace(client, '!club:example.org');
      respond = (request) => request.url.path.contains('/state/')
          ? http.Response(
              jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
              403,
            )
          : null;

      await expectLater(
        createCommunityRoom(club, name: 'Gear swap'),
        throwsA(
          isA<RoomNotAddedToCommunity>().having(
            (e) => e.roomId,
            'roomId',
            '!new:example.org',
          ),
        ),
      );
      expect(communityChildIds(club), isEmpty);
    });

    test('leaving a community leaves the rooms only it holds, then the '
        'community', () async {
      final only = addRoom(client, '!only:example.org', at: at(10));
      final shared = addRoom(client, '!shared:example.org', at: at(9));
      final club = addSpace(
        client,
        '!club:example.org',
        children: [only.id, shared.id],
      );
      addSpace(client, '!other:example.org', children: [shared.id]);

      await leaveCommunity(club);

      final left = [
        for (final r in requests)
          if (r.url.path.endsWith('/leave')) Uri.decodeComponent(r.url.path),
      ];
      expect(left, [
        '/_matrix/client/v3/rooms/${only.id}/leave',
        '/_matrix/client/v3/rooms/${club.id}/leave',
      ]);
    });

    test('a room that cannot be left keeps the community joined', () async {
      final only = addRoom(client, '!only:example.org', at: at(10));
      final club = addSpace(client, '!club:example.org', children: [only.id]);
      respond = (request) =>
          Uri.decodeComponent(request.url.path).contains(only.id)
          ? http.Response(
              jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
              403,
            )
          : null;

      await expectLater(leaveCommunity(club), throwsA(isA<MatrixException>()));
      expect(
        requests.where(
          (r) => Uri.decodeComponent(r.url.path).contains('${club.id}/leave'),
        ),
        isEmpty,
      );
    });

    test('a community whose listed rooms are all joined asks the server '
        'nothing', () async {
      final gear = addRoom(client, '!gear:example.org');
      final club = addSpace(client, '!club:example.org', children: [gear.id]);

      expect(await joinableCommunityRooms(club), isEmpty);
      expect(requests, isEmpty);
    });

    test(
      'joinable rooms come from one hierarchy request and leave out the '
      'community itself, other communities and rooms already joined',
      () async {
        addRoom(client, '!joined:example.org');
        final club = addSpace(
          client,
          '!club:example.org',
          children: [
            '!joined:example.org',
            '!nested:example.org',
            '!open:example.org',
          ],
        );
        Map<String, Object?> chunk(String id, {String? type}) => {
          'room_id': id,
          'name': id,
          'num_joined_members': 3,
          'guest_can_join': false,
          'world_readable': false,
          'children_state': <Object>[],
          'room_type': ?type,
        };
        respond = (request) => http.Response(
          jsonEncode({
            'rooms': [
              chunk(club.id, type: 'm.space'),
              chunk('!joined:example.org'),
              chunk('!nested:example.org', type: 'm.space'),
              chunk('!open:example.org'),
            ],
          }),
          200,
        );

        final rooms = await joinableCommunityRooms(club);

        expect(rooms.map((r) => r.roomId), ['!open:example.org']);
        final request = requests.single;
        expect(request.url.path, endsWith('/hierarchy'));
        expect(request.url.queryParameters['max_depth'], '1');
      },
    );
  });
}
