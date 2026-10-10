import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/notifications/notification_action_target.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('newestAtOrBefore', () {
    test('picks the newest event at or before the bound', () {
      expect(
        newestAtOrBefore([
          (id: r'$a', ts: 1000),
          (id: r'$b', ts: 1999),
          (id: r'$c', ts: 2000),
        ], 1999),
        r'$b',
      );
    });

    test('nothing at or before the bound picks nothing', () {
      expect(newestAtOrBefore([(id: r'$a', ts: 5000)], 1999), isNull);
      expect(newestAtOrBefore(const [], 1999), isNull);
    });
  });

  group('resolveMarkReadEvent', () {
    late int localCalls;
    late List<int> asked;

    setUp(() {
      localCalls = 0;
      asked = [];
    });

    Future<List<TimedEvent>> Function() local(List<TimedEvent> events) =>
        () async {
          localCalls++;
          return events;
        };

    Future<TimedEvent?> Function(int) remote(TimedEvent? found) =>
        (bound) async {
          asked.add(bound);
          return found;
        };

    test('an event id from the notification is used as is', () async {
      expect(
        await resolveMarkReadEvent(
          eventId: r'$e',
          eventSeconds: 1790000000,
          lastEvent: null,
          local: local(const []),
          remote: remote(null),
        ),
        r'$e',
      );
      expect(localCalls, 0);
      expect(asked, isEmpty);
    });

    test(
      'without an event time the room is read up to its last event',
      () async {
        expect(
          await resolveMarkReadEvent(
            eventId: null,
            eventSeconds: null,
            lastEvent: (id: r'$last', ts: 1),
            local: local(const []),
            remote: remote(null),
          ),
          r'$last',
        );
        expect(asked, isEmpty);
      },
    );

    test('a store that holds the notified second marks the newest event of '
        'that second, without asking the server', () async {
      final picked = await resolveMarkReadEvent(
        eventId: null,
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
        eventId: null,
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
          eventId: null,
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
        eventId: null,
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
        eventId: null,
        eventSeconds: 1790000000,
        lastEvent: (id: r'$old', ts: 1789990000000),
        local: local(const []),
        remote: (bound) async => throw Exception('offline'),
      );
      expect(picked, r'$old');
    });

    test('a server answer past the notified second is not used', () async {
      final picked = await resolveMarkReadEvent(
        eventId: null,
        eventSeconds: 1790000000,
        lastEvent: (id: r'$old', ts: 1789990000000),
        local: local(const []),
        remote: remote((id: r'$later', ts: 1790000001000)),
      );
      expect(picked, r'$old');
    });

    test('a store that cannot be read counts as empty', () async {
      final picked = await resolveMarkReadEvent(
        eventId: null,
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
          eventId: null,
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
          httpClient: MockClient((request) async {
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

    test('a message still being sent is never the one marked', () async {
      final client = buildTestClient(userId: '@me:example.org');
      final room = buildTestRoom(client);
      room.lastEvent = buildTestEvent(
        room,
        eventId: 'zuno-notification-1',
        senderId: '@me:example.org',
        status: EventStatus.sending,
      );

      expect(await markReadEventIn(room), isNull);
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
