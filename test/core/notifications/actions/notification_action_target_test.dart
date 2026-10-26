import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/notifications/actions/notification_action_target.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveMarkReadEvent', () {
    late List<int> asked;

    setUp(() {
      asked = [];
    });

    Future<List<TimedEvent>> Function() local(List<TimedEvent> events) =>
        () async => events;

    Future<TimedEvent?> Function(int) remote(TimedEvent? found) =>
        (bound) async {
          asked.add(bound);
          return found;
        };

    test('a store that holds the notified second marks the newest event of '
        'that second, without asking the server', () async {
      final picked = await resolveMarkReadEvent(
        eventSeconds: 1790000000,
        lastEvent: (id: r'$later', ts: 1790000005000),
        local: local([
          (id: r'$at', ts: 1790000000500),
          (id: r'$before', ts: 1789999999000),
        ]),
        remote: remote((id: r'$server', ts: 1790000000400)),
      );
      expect(picked, r'$at');
      expect(asked, isEmpty);
    });

    test('a store that has not caught up asks the server for the event at the '
        'end of the notified second', () async {
      final picked = await resolveMarkReadEvent(
        eventSeconds: 1790000000,
        lastEvent: (id: r'$old', ts: 1789990000000),
        local: local([(id: r'$older', ts: 1789980000000)]),
        remote: remote((id: r'$notified', ts: 1790000000250)),
      );
      expect(picked, r'$notified');
      expect(asked, [1790000000999]);
    });

    test(
      'a busy room whose stored events are all newer asks the server',
      () async {
        final picked = await resolveMarkReadEvent(
          eventSeconds: 1790000000,
          lastEvent: (id: r'$newest', ts: 1790000090000),
          local: local([
            for (var i = 0; i < 30; i++)
              (id: '\$n$i', ts: 1790000060000 + i * 1000),
          ]),
          remote: remote((id: r'$notified', ts: 1790000000250)),
        );
        expect(picked, r'$notified');
        expect(asked, hasLength(1));
      },
    );

    test('a gap around the notified second asks the server instead of marking '
        'an older stored event', () async {
      final picked = await resolveMarkReadEvent(
        eventSeconds: 1790000000,
        lastEvent: (id: r'$after', ts: 1790000300000),
        local: local([
          (id: r'$after', ts: 1790000300000),
          (id: r'$before', ts: 1789999000000),
        ]),
        remote: remote((id: r'$notified', ts: 1790000000250)),
      );
      expect(picked, r'$notified');
      expect(asked, hasLength(1));
    });

    test('if the server cannot be asked, the newest stored event before the '
        'notification is marked', () async {
      final picked = await resolveMarkReadEvent(
        eventSeconds: 1790000000,
        lastEvent: (id: r'$old', ts: 1789990000000),
        local: local(const []),
        remote: (bound) async => throw Exception('offline'),
      );
      expect(picked, r'$old');
    });

    test('a server answer past the notified second is not used', () async {
      final picked = await resolveMarkReadEvent(
        eventSeconds: 1790000000,
        lastEvent: (id: r'$old', ts: 1789990000000),
        local: local(const []),
        remote: remote((id: r'$later', ts: 1790000001000)),
      );
      expect(picked, r'$old');
    });

    test('a store that cannot be read counts as empty', () async {
      final picked = await resolveMarkReadEvent(
        eventSeconds: 1790000000,
        lastEvent: null,
        local: () async => throw Exception('locked'),
        remote: remote((id: r'$notified', ts: 1790000000000)),
      );
      expect(picked, r'$notified');
    });

    test('nothing known anywhere marks nothing', () async {
      expect(
        await resolveMarkReadEvent(
          eventSeconds: 1790000000,
          lastEvent: null,
          local: local(const []),
          remote: remote(null),
        ),
        isNull,
      );
    });
  });

  group('markReadEventIn', () {
    test(
      'asks the server for the event at the end of the notified second',
      () async {
        final requests = <Uri>[];
        final client = buildTestClient(
          userId: '@me:example.org',
          httpClient: FakeHttpClient((request) async {
            requests.add(request.url);
            return http.Response(
              jsonEncode({
                'event_id': r'$notified',
                'origin_server_ts': 1790000000250,
              }),
              200,
            );
          }),
        );
        client.baseUri = Uri.parse('https://example.org');
        client.bearerToken = 'test-token';

        final picked = await markReadEventIn(
          buildTestRoom(client),
          eventSeconds: 1790000000,
        );

        expect(picked, r'$notified');
        expect(requests.single.path, endsWith('/timestamp_to_event'));
        expect(requests.single.queryParameters, {
          'ts': '1790000000999',
          'dir': 'b',
        });
      },
    );

    test('an event id from the notification is used as is', () async {
      final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));

      expect(
        await markReadEventIn(room, eventId: r'$e', eventSeconds: 1790000000),
        r'$e',
      );
    });

    test('without an event time, a message still being sent is skipped for '
        'the newest stored server event', () async {
      final database = StoredEventsFakeDatabaseApi();
      final room = buildTestRoom(
        buildTestClient(userId: '@me:example.org', database: database),
      );
      final sending = buildTestEvent(
        room,
        eventId: 'zuno-notification-1',
        senderId: '@me:example.org',
        status: EventStatus.sending,
      );
      room.lastEvent = sending;
      database.events = [
        sending,
        buildTestEvent(
          room,
          eventId: r'$newest',
          senderId: '@bob:example.org',
          status: EventStatus.synced,
        ),
      ];

      expect(await markReadEventIn(room), r'$newest');
    });
  });

  group('ThreadKeyRooms', () {
    late Client client;

    setUp(() {
      client = buildTestClient(userId: '@me:example.org');
      client.rooms
        ..add(buildTestRoom(client, id: '!a:example.org'))
        ..add(buildTestRoom(client, id: '!b:example.org'));
    });

    test('finds the room whose thread key matches', () async {
      final rooms = ThreadKeyRooms(threadKeyFor: (id) async => 'key-$id');
      expect(
        (await rooms.roomFor(client, 'key-!b:example.org'))?.id,
        '!b:example.org',
      );
    });

    test('an unknown key finds no room', () async {
      final rooms = ThreadKeyRooms(threadKeyFor: (id) async => 'key-$id');
      expect(await rooms.roomFor(client, 'key-!gone:example.org'), isNull);
    });

    test('a key that could not be read is asked for again next time', () async {
      var first = true;
      final rooms = ThreadKeyRooms(
        threadKeyFor: (id) async {
          if (id == '!a:example.org' && first) {
            first = false;
            return null;
          }
          return 'key-$id';
        },
      );
      expect(await rooms.roomFor(client, 'key-!a:example.org'), isNull);
      expect(
        (await rooms.roomFor(client, 'key-!a:example.org'))?.id,
        '!a:example.org',
      );
    });
  });
}
