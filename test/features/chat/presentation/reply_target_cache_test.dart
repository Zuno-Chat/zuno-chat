import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/reply_target_cache.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
  });

  test('repeated fetches look up once', () async {
    var lookups = 0;
    final target = buildTestEvent(
      room,
      eventId: r'$a',
      senderId: '@bob:example.org',
    );
    final cache = ReplyTargetCache((id) async {
      lookups++;
      return target;
    });

    final results = await Future.wait([
      cache.fetch(r'$a'),
      cache.fetch(r'$a'),
      cache.fetch(r'$a'),
    ]);

    expect(lookups, 1);
    expect(results, everyElement(same(target)));
    expect(cache.isResolved(r'$a'), isTrue);
    expect(cache.resolved(r'$a'), same(target));
  });

  test('not available is remembered', () async {
    var lookups = 0;
    final cache = ReplyTargetCache((id) async {
      lookups++;
      return null;
    });

    expect(cache.isResolved(r'$gone'), isFalse);
    expect(await cache.fetch(r'$gone'), isNull);
    expect(await cache.fetch(r'$gone'), isNull);

    expect(lookups, 1);
    expect(cache.isResolved(r'$gone'), isTrue);
    expect(cache.resolved(r'$gone'), isNull);
  });

  test('a failing lookup resolves to not available', () async {
    var lookups = 0;
    final cache = ReplyTargetCache((id) async {
      lookups++;
      throw Exception('offline');
    });

    expect(await cache.fetch(r'$a'), isNull);
    expect(await cache.fetch(r'$a'), isNull);

    expect(lookups, 1);
    expect(cache.isResolved(r'$a'), isTrue);
  });

  test('ids are looked up independently', () async {
    final seen = <String>[];
    final cache = ReplyTargetCache((id) async {
      seen.add(id);
      return null;
    });

    await cache.fetch(r'$a');
    await cache.fetch(r'$b');

    expect(seen, [r'$a', r'$b']);
  });
}
