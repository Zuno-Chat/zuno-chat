import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/reactions.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

class _ReactionsDatabase extends StoredEventsFakeDatabaseApi
    with SendCapableDatabase {
  @override
  Future<void> removeEvent(String eventId, String roomId) async {}
}

void main() {
  late _ReactionsDatabase db;
  late List<http.Request> requests;
  late Room room;
  late Event message;
  late List<Map<String, Object?>> serverRelations;
  late List<Map<String, Object?>> secondRelationsPage;

  setUp(() {
    requests = [];
    serverRelations = [];
    secondRelationsPage = [];
    db = _ReactionsDatabase();
    final client = buildTestClient(
      userId: '@me:example.org',
      database: db,
      httpClient: FakeHttpClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/relations/')) {
          final second = request.url.queryParameters['from'] == 'page2';
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'chunk': second ? secondRelationsPage : serverRelations,
                if (!second && secondRelationsPage.isNotEmpty)
                  'next_batch': 'page2',
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'event_id': r'$new'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'token';
    room = buildTestRoom(client)..partial = false;
    message = buildTestEvent(
      room,
      eventId: r'$message',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'hi'},
    );
  });

  Event reaction(
    String eventId,
    String senderId,
    String? key, {
    bool redacted = false,
    EventStatus? status,
  }) {
    final event = buildTestEvent(
      room,
      eventId: eventId,
      senderId: senderId,
      type: EventTypes.Reaction,
      status: status,
      content: {
        'm.relates_to': {
          'rel_type': RelationshipTypes.reaction,
          'event_id': message.eventId,
          'key': ?key,
        },
      },
    );
    if (redacted) {
      event.unsigned = {
        'redacted_because': {
          'event_id': r'$redaction',
          'type': EventTypes.Redaction,
          'sender': senderId,
          'content': {},
          'origin_server_ts': 0,
        },
      };
    }
    return event;
  }

  Future<Timeline> timelineWith(List<Event> reactions) async {
    db.events = [...reactions.reversed, message];
    final timeline = await room.getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    return timeline;
  }

  Iterable<String> redacted() => requests
      .where((r) => r.url.path.contains('/redact/'))
      .map((r) => r.url.pathSegments[r.url.pathSegments.indexOf('redact') + 1]);

  Iterable<String> sentKeys() => requests
      .where((r) => r.url.path.contains('/send/m.reaction/'))
      .map((r) => (jsonDecode(r.body) as Map)['m.relates_to']['key'] as String);

  group('reactionSummaries', () {
    test('counts each key and marks the ones I used', () async {
      final timeline = await timelineWith([
        reaction(r'$r1', '@bob:example.org', '👍'),
        reaction(r'$r2', '@me:example.org', '👍'),
        reaction(r'$r3', '@carol:example.org', '😂'),
      ]);

      final summaries = {
        for (final s in reactionSummaries(message, timeline))
          s.key: (s.count, s.reactedByMe),
      };

      expect(summaries, {'👍': (2, true), '😂': (1, false)});
    });

    test('skips redacted reactions and reactions without a key', () async {
      final timeline = await timelineWith([
        reaction(r'$r1', '@bob:example.org', '👍', redacted: true),
        reaction(r'$r2', '@bob:example.org', null),
      ]);

      expect(reactionSummaries(message, timeline), isEmpty);
    });
  });

  group('reactions from the server', () {
    Map<String, Object?> raw(String id, String sender, String key) => {
      'event_id': id,
      'type': EventTypes.Reaction,
      'sender': sender,
      'room_id': room.id,
      'origin_server_ts': 0,
      'content': {
        'm.relates_to': {
          'rel_type': RelationshipTypes.reaction,
          'event_id': message.eventId,
          'key': key,
        },
      },
    };

    test('fetchReactions reads every page the server has', () async {
      serverRelations = [raw(r'$r1', '@bob:example.org', '👍')];
      secondRelationsPage = [raw(r'$r2', '@me:example.org', '😂')];

      final fetched = await fetchReactions(message);

      expect(fetched.map((e) => e.eventId), [r'$r1', r'$r2']);
    });

    test(
      'toggling finds my reaction on a later page and takes it back',
      () async {
        final timeline = await timelineWith([]);
        serverRelations = [raw(r'$r1', '@bob:example.org', '👍')];
        secondRelationsPage = [raw(r'$mine', '@me:example.org', '😂')];

        await toggleReaction(
          buildTestEvent(
            room,
            eventId: r'$older',
            senderId: '@bob:example.org',
            content: {'msgtype': 'm.image', 'body': 'a.jpg'},
          ),
          timeline,
          '😂',
        );

        expect(redacted(), [r'$mine']);
        expect(sentKeys(), isEmpty);
      },
    );

    test(
      'fetchReactions asks the server for every reaction to a message',
      () async {
        serverRelations = [
          raw(r'$r1', '@bob:example.org', '👍'),
          raw(r'$r2', '@me:example.org', '😂'),
        ];

        final fetched = await fetchReactions(message);

        expect(fetched.map((e) => e.eventId), [r'$r1', r'$r2']);
      },
    );

    test(
      'fetched reactions count alongside the timeline\'s, each once',
      () async {
        final timeline = await timelineWith([
          reaction(r'$r1', '@bob:example.org', '👍'),
        ]);
        serverRelations = [
          raw(r'$r1', '@bob:example.org', '👍'),
          raw(r'$r2', '@me:example.org', '👍'),
          raw(r'$r3', '@carol:example.org', '😂'),
        ];

        final summaries = {
          for (final s in reactionSummaries(
            message,
            timeline,
            fetched: await fetchReactions(message),
          ))
            s.key: (s.count, s.reactedByMe),
        };

        expect(summaries, {'👍': (2, true), '😂': (1, false)});
      },
    );
  });

  group('toggleReaction', () {
    test('for a message outside the loaded timeline, it asks the server for '
        'my reaction and takes it back', () async {
      final timeline = await timelineWith([]);
      db.events = [];
      final older = buildTestEvent(
        room,
        eventId: r'$older',
        senderId: '@bob:example.org',
        content: {'msgtype': 'm.image', 'body': 'a.jpg'},
      );
      serverRelations = [
        {
          'event_id': r'$mine',
          'type': EventTypes.Reaction,
          'sender': '@me:example.org',
          'room_id': room.id,
          'origin_server_ts': 0,
          'content': {
            'm.relates_to': {
              'rel_type': RelationshipTypes.reaction,
              'event_id': r'$older',
              'key': '👍',
            },
          },
        },
      ];

      await toggleReaction(older, timeline, '👍');

      expect(
        requests.where(
          (r) =>
              r.url.pathSegments.contains('relations') &&
              r.url.pathSegments.contains(r'$older'),
        ),
        isNotEmpty,
      );
      expect(redacted(), [r'$mine']);
      expect(sentKeys(), isEmpty);
    });

    test('adds my reaction when I have none', () async {
      final timeline = await timelineWith([
        reaction(r'$r1', '@bob:example.org', '👍'),
      ]);

      await toggleReaction(message, timeline, '👍');

      expect(redacted(), isEmpty);
      expect(sentKeys(), ['👍']);
    });

    test('tapping my own reaction again takes it back', () async {
      final timeline = await timelineWith([
        reaction(r'$mine', '@me:example.org', '👍'),
      ]);

      await toggleReaction(message, timeline, '👍');

      expect(redacted(), [r'$mine']);
      expect(sentKeys(), isEmpty);
    });

    test('a different key replaces my reaction', () async {
      final timeline = await timelineWith([
        reaction(r'$mine', '@me:example.org', '👍'),
      ]);

      await toggleReaction(message, timeline, '😂');

      expect(redacted(), [r'$mine']);
      expect(sentKeys(), ['😂']);
    });

    test('a reaction of mine that never went out is dropped, not deleted on '
        'the server', () async {
      final timeline = await timelineWith([
        reaction(
          'txn-mine',
          '@me:example.org',
          '👍',
          status: EventStatus.error,
        ),
      ]);

      await toggleReaction(message, timeline, '😂');

      expect(redacted(), isEmpty);
      expect(sentKeys(), ['😂']);
      expect(reactionSummaries(message, timeline).map((s) => s.key), ['😂']);
    });

    test(
      'taking back a reaction of mine that never went out sends nothing',
      () async {
        final timeline = await timelineWith([
          reaction(
            'txn-mine',
            '@me:example.org',
            '👍',
            status: EventStatus.error,
          ),
        ]);

        await toggleReaction(message, timeline, '👍');
        await Future<void>.delayed(Duration.zero);

        expect(requests, isEmpty);
        expect(reactionSummaries(message, timeline), isEmpty);
      },
    );

    test('a reaction of mine still on its way is left to land', () async {
      final timeline = await timelineWith([
        reaction(
          'txn-mine',
          '@me:example.org',
          '👍',
          status: EventStatus.sending,
        ),
      ]);

      await toggleReaction(message, timeline, '😂');

      expect(requests, isEmpty);
    });

    test('a reaction of mine already taken back is left alone', () async {
      final timeline = await timelineWith([
        reaction(r'$old', '@me:example.org', '👍', redacted: true),
      ]);

      await toggleReaction(message, timeline, '👍');

      expect(redacted(), isEmpty);
      expect(sentKeys(), ['👍']);
    });
  });
}
