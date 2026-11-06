import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/rooms/membership/rooms_in_common.dart';

import '../../../../helpers/fake_http.dart';
import '../../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room here;
  late List<http.Request> requests;
  late Map<String, Object?> versions;
  late List<Map<String, Object?>> pages;

  setUp(() {
    requests = [];
    versions = {
      'versions': ['v1.17'],
      'unstable_features': {
        'uk.half-shot.msc2666.query_mutual_rooms.stable': true,
      },
    };
    pages = [];
    client = buildTestClient(
      userId: '@me:example.org',
      database: CachingFakeDatabaseApi(),
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/versions')) {
          return http.Response(jsonEncode(versions), 200);
        }
        if (request.url.path.endsWith('/mutual_rooms')) {
          return http.Response(jsonEncode(pages.removeAt(0)), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    here = namedRoom(client, '!here:example.org', 'Here');
    client.rooms.add(here);
  });

  Room addRoom(String id, String name, {DateTime? active}) {
    final room = namedRoom(client, id, name);
    if (active != null) {
      room.lastEvent = buildTestEvent(
        room,
        eventId: '\$last-$id',
        senderId: '@ann:example.org',
        originServerTs: active,
      );
    }
    client.rooms.add(room);
    return room;
  }

  Iterable<http.Request> mutualRoomRequests() =>
      requests.where((r) => r.url.path.endsWith('/mutual_rooms'));

  test('lists the other rooms you share, newest activity first', () async {
    addRoom('!old:example.org', 'Old', active: DateTime(2026, 1, 1));
    addRoom('!new:example.org', 'New', active: DateTime(2026, 6, 1));
    pages.add({
      'joined': ['!here:example.org', '!old:example.org', '!new:example.org'],
      'count': 3,
    });

    final rooms = await roomsInCommon(here, '@ann:example.org');

    expect(rooms.map((room) => room.id), [
      '!new:example.org',
      '!old:example.org',
    ]);
    expect(
      mutualRoomRequests().single.url.queryParameters['user_id'],
      '@ann:example.org',
    );
  });

  test('leaves out chats, communities and rooms Zuno does not know', () async {
    addRoom('!group:example.org', 'Group');
    final chat = addRoom('!chat:example.org', 'Chat');
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@ann:example.org': [chat.id],
      },
    );
    final community = addRoom('!community:example.org', 'Community');
    community.setState(
      buildTestEvent(
        community,
        eventId: r'$create',
        senderId: '@ann:example.org',
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    addRoom('!invited:example.org', 'Invited').membership = Membership.invite;
    pages.add({
      'joined': [
        '!group:example.org',
        '!chat:example.org',
        '!community:example.org',
        '!invited:example.org',
        '!unknown:example.org',
      ],
      'count': 5,
    });

    final rooms = await roomsInCommon(here, '@ann:example.org');

    expect(rooms.map((room) => room.id), ['!group:example.org']);
  });

  test('follows every page the server hands out', () async {
    addRoom('!a:example.org', 'A');
    addRoom('!b:example.org', 'B');
    pages
      ..add({
        'joined': ['!a:example.org'],
        'next_batch': 'next',
        'count': 2,
      })
      ..add({
        'joined': ['!b:example.org'],
        'count': 2,
      });

    final rooms = await roomsInCommon(here, '@ann:example.org');

    expect(rooms.map((room) => room.id).toSet(), {
      '!a:example.org',
      '!b:example.org',
    });
    expect(mutualRoomRequests().last.url.queryParameters['from'], 'next');
  });

  test('asks a server on Matrix 1.19 or later without the flag', () async {
    versions = {
      'versions': ['v1.18', 'v1.19'],
    };
    addRoom('!a:example.org', 'A');
    pages.add({
      'joined': ['!a:example.org'],
      'count': 1,
    });

    final rooms = await roomsInCommon(here, '@ann:example.org');

    expect(rooms, hasLength(1));
  });

  test('asks nothing of a server that cannot answer', () async {
    versions = {
      'versions': ['v1.17', 'v1.2'],
      'unstable_features': {
        'uk.half-shot.msc2666.query_mutual_rooms.stable': false,
      },
    };
    addRoom('!a:example.org', 'A');

    final rooms = await roomsInCommon(here, '@ann:example.org');

    expect(rooms, isEmpty);
    expect(mutualRoomRequests(), isEmpty);
  });
}
