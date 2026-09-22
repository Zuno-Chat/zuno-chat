import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/mention_query.dart';

import '../../../helpers/fake_matrix.dart';

MentionQuery? at(String text, [int? cursor]) =>
    mentionQueryAt(text, cursor ?? text.length);

void main() {
  group('mentionQueryAt', () {
    test('a lone @ at the start asks for everyone', () {
      expect(at('@'), const MentionQuery(start: 0, text: ''));
    });

    test('@ after a space with letters is a query', () {
      expect(at('hi @al'), const MentionQuery(start: 3, text: 'al'));
    });

    test('an @ inside a word, like an email, is not a mention', () {
      expect(at('mail me at foo@bar'), isNull);
      expect(at('@@'), isNull);
    });

    test('a space after the @ ends the mention', () {
      expect(at('@ '), isNull);
      expect(at('@bob hi'), isNull);
      expect(at('@\n'), isNull);
    });

    test('only text before the cursor counts', () {
      expect(at('@alice', 3), const MentionQuery(start: 0, text: 'al'));
      expect(at('@alice', 0), isNull);
    });

    test('the last @ wins', () {
      expect(at('@bob hi @c'), const MentionQuery(start: 8, text: 'c'));
    });

    test('every character a Matrix localpart allows can follow the @', () {
      expect(at('@bo-b'), const MentionQuery(start: 0, text: 'bo-b'));
      expect(at('@a+b=c/d'), const MentionQuery(start: 0, text: 'a+b=c/d'));
      expect(at('@a.b_c1'), const MentionQuery(start: 0, text: 'a.b_c1'));
      expect(at('@Bo'), const MentionQuery(start: 0, text: 'Bo'));
    });

    test('a character no localpart can hold ends the mention', () {
      expect(at('@bob!'), isNull);
      expect(at('@bob?'), isNull);
      expect(at('@bob:zuno.chat'), isNull);
    });

    test('an out-of-range cursor is not a mention', () {
      expect(at('@al', -1), isNull);
      expect(at('@al', 10), isNull);
    });
  });

  group('mentionMatches', () {
    final client = buildTestClient(userId: '@me:example.org');
    final room = buildTestRoom(client);
    final members = [
      User(
        '@bob:example.org',
        membership: 'join',
        displayName: 'Bobby',
        room: room,
      ),
      User(
        '@alice:example.org',
        membership: 'join',
        displayName: 'Alice',
        room: room,
      ),
      User('@carol:example.org', membership: 'join', room: room),
    ];

    test('an empty query lists everyone by name', () {
      expect(mentionMatches(members, '').map((u) => u.id), [
        '@alice:example.org',
        '@bob:example.org',
        '@carol:example.org',
      ]);
    });

    test('matches display name or username, ignoring case', () {
      expect(mentionMatches(members, 'BO').map((u) => u.id), [
        '@bob:example.org',
      ]);
      expect(mentionMatches(members, 'car').map((u) => u.id), [
        '@carol:example.org',
      ]);
      expect(mentionMatches(members, 'zed'), isEmpty);
    });
  });

  test('applyMention swaps the query for the mention and a space', () {
    final result = applyMention(
      'hi @al there',
      const MentionQuery(start: 3, text: 'al'),
      cursor: 6,
      insert: '@alice',
    );

    expect(result.text, 'hi @alice  there');
    expect(result.cursor, 10);
  });

  test('mentionMatches caps the list', () {
    final client = buildTestClient(userId: '@me:example.org');
    final room = buildTestRoom(client);
    final many = [
      for (var i = 0; i < 40; i++)
        User(
          '@u$i:example.org',
          membership: 'join',
          displayName: 'User $i',
          room: room,
        ),
    ];

    expect(mentionMatches(many, '', limit: 30), hasLength(30));
  });

  group('mentionInsertText', () {
    final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));

    test('uses the display-name fragment the SDK resolves', () {
      expect(
        mentionInsertText(
          User(
            '@alice:example.org',
            membership: 'join',
            displayName: 'Alice',
            room: room,
          ),
        ),
        '@Alice',
      );
      expect(
        mentionInsertText(
          User(
            '@alice:example.org',
            membership: 'join',
            displayName: 'Alice Smith',
            room: room,
          ),
        ),
        '@[Alice Smith]',
      );
    });

    test('falls back to the username without a display name', () {
      expect(
        mentionInsertText(
          User('@alice:example.org', membership: 'join', room: room),
        ),
        '@alice',
      );
    });
  });
}
