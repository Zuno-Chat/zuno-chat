import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/rooms/joinable_rooms_feed.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _club = '!club:example.org';

void main() {
  late Client client;
  late Room club;
  late List<String?> asked;
  late FutureOr<GetSpaceHierarchyResponse> Function(String? from) answer;

  Room space(Client client) {
    final room = buildTestRoom(client, id: _club)..membership = Membership.join;
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$create',
        senderId: _me,
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'type': RoomCreationTypes.mSpace},
      ),
    );
    client.rooms.add(room);
    return room;
  }

  void list(List<String> ids) {
    for (final id in ids) {
      club.setState(
        buildTestEvent(
          club,
          eventId: '\$child-$id',
          senderId: _me,
          type: EventTypes.SpaceChild,
          stateKey: id,
          content: {
            'via': ['example.org'],
          },
        ),
      );
    }
  }

  void join(String id) => client.rooms.add(
    buildTestRoom(client, id: id)..membership = Membership.join,
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

  GetSpaceHierarchyResponse page(List<String> ids, {String? next}) =>
      GetSpaceHierarchyResponse(
        nextBatch: next,
        rooms: [for (final id in ids) SpaceRoomsChunk$2.fromJson(chunk(id))],
      );

  JoinableRoomsFeed feed() {
    final feed = JoinableRoomsFeed(
      club,
      loadPage: (community, {from}) async {
        asked.add(from);
        return answer(from);
      },
    );
    addTearDown(feed.dispose);
    return feed;
  }

  List<String> shown(JoinableRoomsFeed feed) => [
    for (final room in feed.rooms!) room.roomId,
  ];

  setUp(() {
    client = buildTestClient(userId: _me);
    club = space(client);
    asked = [];
    list(['!a:example.org', '!b:example.org', '!c:example.org']);
  });

  group('the first page', () {
    test('leaves out the community, other communities and rooms you are '
        'in', () async {
      join('!joined:example.org');
      answer = (_) => GetSpaceHierarchyResponse.fromJson({
        'rooms': [
          chunk(_club, type: RoomCreationTypes.mSpace),
          chunk('!joined:example.org'),
          chunk('!nested:example.org', type: RoomCreationTypes.mSpace),
          chunk('!a:example.org'),
        ],
      });
      final rooms = feed();

      await rooms.refresh();

      expect(shown(rooms), ['!a:example.org']);
      expect(rooms.hasMore, isFalse);
    });

    test('a community listing only rooms you are in asks nothing', () async {
      for (final id in ['!a:example.org', '!b:example.org', '!c:example.org']) {
        join(id);
      }
      final rooms = feed();

      await rooms.refresh();

      expect(rooms.rooms, isEmpty);
      expect(rooms.hasMore, isFalse);
      expect(asked, isEmpty);
    });

    test('is asked of the server one level deep, 20 rooms at a time', () async {
      final requests = <http.Request>[];
      client = buildTestClient(
        userId: _me,
        httpClient: FakeHttpClient((request) async {
          requests.add(request);
          final first = request.url.queryParameters['from'] == null;
          return http.Response(
            jsonEncode({
              'rooms': [chunk(first ? '!a:example.org' : '!b:example.org')],
              if (first) 'next_batch': 'p2',
            }),
            200,
          );
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'test-token';
      club = space(client);
      list(['!a:example.org', '!b:example.org']);
      final rooms = JoinableRoomsFeed(club, loadPage: communityRoomsPage);
      addTearDown(rooms.dispose);

      await rooms.refresh();
      await rooms.loadMore();

      expect(shown(rooms), ['!a:example.org', '!b:example.org']);
      expect(
        requests.map((r) => Uri.decodeComponent(r.url.path)),
        everyElement('/_matrix/client/v1/rooms/$_club/hierarchy'),
      );
      expect(requests.map((r) => r.url.queryParameters), [
        {'max_depth': '1', 'limit': '20'},
        {'max_depth': '1', 'limit': '20', 'from': 'p2'},
      ]);
    });

    test('a first page that fails is tried again from the start', () async {
      var calls = 0;
      answer = (_) =>
          calls++ == 0 ? throw Exception('offline') : page(['!a:example.org']);
      final rooms = feed();

      await rooms.refresh();
      expect(rooms.failed, isTrue);
      expect(rooms.rooms, isNull);

      await rooms.retry();

      expect(asked, [null, null]);
      expect(shown(rooms), ['!a:example.org']);
      expect(rooms.failed, isFalse);
    });
  });

  group('more pages', () {
    test('continue from where the last ended, until the server has no '
        'more', () async {
      answer = (from) => from == null
          ? page(['!a:example.org'], next: 'p2')
          : page(['!b:example.org']);
      final rooms = feed();

      await rooms.refresh();
      expect(rooms.hasMore, isTrue);
      await rooms.loadMore();
      await rooms.loadMore();

      expect(shown(rooms), ['!a:example.org', '!b:example.org']);
      expect(asked, [null, 'p2']);
      expect(rooms.hasMore, isFalse);
    });

    test('a page with nothing new to join loads the next straight '
        'away', () async {
      join('!gear:example.org');
      answer = (from) => switch (from) {
        null => page(['!gear:example.org'], next: 'p2'),
        'p2' => page(['!gear:example.org'], next: 'p3'),
        _ => page(['!a:example.org'], next: 'p4'),
      };
      final rooms = feed();

      await rooms.refresh();

      expect(asked, [null, 'p2', 'p3']);
      expect(shown(rooms), ['!a:example.org']);
      expect(rooms.hasMore, isTrue);
    });

    test('once the server forgets the position, the list starts over '
        'without repeating rooms', () async {
      var starts = 0;
      answer = (from) => switch (from) {
        null when starts++ == 0 => page(['!a:example.org'], next: 'p2'),
        null => page(['!a:example.org'], next: 'q2'),
        'p2' => throw MatrixException.fromJson({
          'errcode': 'M_INVALID_PARAM',
          'error': 'Unknown pagination token',
        }),
        _ => page(['!b:example.org']),
      };
      final rooms = feed();

      await rooms.refresh();
      await rooms.loadMore();

      expect(asked, [null, 'p2', null, 'q2']);
      expect(shown(rooms), ['!a:example.org', '!b:example.org']);
      expect(rooms.failed, isFalse);
      expect(rooms.hasMore, isFalse);
    });

    test('a later page that fails keeps the rooms, and trying again asks '
        'for that page again', () async {
      var later = 0;
      answer = (from) => switch (from) {
        null => page(['!a:example.org'], next: 'p2'),
        _ when later++ == 0 => throw Exception('offline'),
        _ => page(['!b:example.org']),
      };
      final rooms = feed();
      await rooms.refresh();

      await rooms.loadMore();
      expect(rooms.failed, isTrue);
      expect(shown(rooms), ['!a:example.org']);
      await rooms.loadMore();
      expect(asked, [null, 'p2']);

      await rooms.retry();

      expect(asked, [null, 'p2', 'p2']);
      expect(shown(rooms), ['!a:example.org', '!b:example.org']);
      expect(rooms.failed, isFalse);
    });
  });

  group('refreshing', () {
    test('starts over and replaces the rooms', () async {
      var starts = 0;
      answer = (from) => switch (from) {
        null when starts++ == 0 => page(['!a:example.org'], next: 'p2'),
        null => page(['!c:example.org']),
        _ => page(['!b:example.org']),
      };
      final rooms = feed();
      await rooms.refresh();
      await rooms.loadMore();

      await rooms.refresh();

      expect(shown(rooms), ['!c:example.org']);
      expect(rooms.hasMore, isFalse);
    });

    test('drops a page that lands after it', () async {
      final lagging = Completer<GetSpaceHierarchyResponse>();
      var starts = 0;
      answer = (from) => switch (from) {
        null when starts++ == 0 => page(['!a:example.org'], next: 'p2'),
        null => page(['!c:example.org']),
        _ => lagging.future,
      };
      final rooms = feed();
      await rooms.refresh();
      final loading = rooms.loadMore();

      await rooms.refresh();
      lagging.complete(page(['!b:example.org']));
      await loading;

      expect(shown(rooms), ['!c:example.org']);
      expect(rooms.loading, isFalse);
      expect(rooms.hasMore, isFalse);
    });
  });

  test('a room you join drops out at once', () async {
    answer = (_) => page(['!a:example.org', '!b:example.org']);
    final rooms = feed();
    await rooms.refresh();

    join('!a:example.org');

    expect(shown(rooms), ['!b:example.org']);
  });

  test('a page that lands after the page closed is ignored', () async {
    final lagging = Completer<GetSpaceHierarchyResponse>();
    final rooms = JoinableRoomsFeed(
      club,
      loadPage: (community, {from}) => lagging.future,
    );
    final loading = rooms.refresh();

    rooms.dispose();
    lagging.complete(page(['!a:example.org']));

    await expectLater(loading, completes);
  });
}
