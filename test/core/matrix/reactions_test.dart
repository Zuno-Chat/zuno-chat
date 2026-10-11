import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/reactions.dart';

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

  setUp(() {
    requests = [];
    db = _ReactionsDatabase();
    final client = buildTestClient(
      userId: '@me:example.org',
      database: db,
      httpClient: MockClient((request) async {
        requests.add(request);
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

  group('toggleReaction', () {
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
