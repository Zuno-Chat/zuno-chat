import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/account/saved_server_answer.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  final at = DateTime(2026, 11, 7, 12);
  late CachingFakeDatabaseApi database;

  setUp(() => database = CachingFakeDatabaseApi());

  test('saveServerAnswer then readSavedServerAnswer round-trips content and '
      'time', () async {
    final client = buildTestClient(
      userId: '@me:example.org',
      database: database,
    );
    await withClock(
      Clock.fixed(at),
      () => saveServerAnswer(client, 'k', {'offer': 'cloudflare', 'n': 2}),
    );
    expect(database.cache['k']!.content, {
      'user_id': '@me:example.org',
      'saved_at': at.millisecondsSinceEpoch,
      'offer': 'cloudflare',
      'n': 2,
    });
    final saved = await readSavedServerAnswer(client, 'k');
    expect(saved!.content, {'offer': 'cloudflare', 'n': 2});
    expect(saved.savedAt, at);
  });

  test('content can never overwrite the account stamp', () async {
    final client = buildTestClient(
      userId: '@me:example.org',
      database: database,
    );

    await withClock(
      Clock.fixed(at),
      () => saveServerAnswer(client, 'k', {
        'user_id': '@you:example.org',
        'saved_at': 1,
        'offer': 'cloudflare',
      }),
    );

    expect(database.cache['k']!.content, {
      'user_id': '@me:example.org',
      'saved_at': at.millisecondsSinceEpoch,
      'offer': 'cloudflare',
    });
  });

  test(
    'readSavedServerAnswer is null for another user or a bad saved_at',
    () async {
      final client = buildTestClient(
        userId: '@me:example.org',
        database: database,
      );
      expect(await readSavedServerAnswer(client, 'missing'), isNull);
      for (final content in <Map<String, Object?>>[
        {'user_id': '@you:example.org', 'saved_at': 1},
        {'user_id': '@me:example.org'},
        {'user_id': '@me:example.org', 'saved_at': '1'},
      ]) {
        database.cache['k'] = (content: content, savedAt: at);
        expect(await readSavedServerAnswer(client, 'k'), isNull);
      }
    },
  );

  test('isFresh holds an answer younger than its lifetime', () {
    const lifetime = Duration(days: 1);
    withClock(Clock.fixed(at), () {
      expect(isFresh(at, lifetime), isTrue);
      expect(isFresh(at.subtract(const Duration(hours: 23)), lifetime), isTrue);
    });
  });

  test('isFresh drops an answer as old as its lifetime or older', () {
    const lifetime = Duration(days: 1);
    withClock(Clock.fixed(at), () {
      expect(isFresh(at.subtract(lifetime), lifetime), isFalse);
      expect(isFresh(at.subtract(const Duration(days: 2)), lifetime), isFalse);
    });
  });

  test('isFresh drops an answer saved in the future, after a clock change', () {
    withClock(Clock.fixed(at), () {
      expect(
        isFresh(at.add(const Duration(minutes: 1)), const Duration(days: 1)),
        isFalse,
      );
    });
  });
}
