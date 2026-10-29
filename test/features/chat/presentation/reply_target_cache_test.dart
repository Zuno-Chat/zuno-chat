import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/reply_target_cache.dart';

import '../../../helpers/fake_encryption.dart';
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

  group('a target still locked', () {
    late FakeRoomDecryption decryption;
    late Room encrypted;

    setUp(() {
      decryption = FakeRoomDecryption();
      encrypted = buildTestRoom(DecryptingTestClient(decryption));
    });

    Event locked() => lockedTestEvent(
      encrypted,
      eventId: r'$a',
      senderId: '@bob:example.org',
    );

    Event opened() => buildTestEvent(
      encrypted,
      eventId: r'$a',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'hi'},
    );

    test('opens once its key arrives, and listeners hear of it', () async {
      final cache = ReplyTargetCache((id) async => locked());
      addTearDown(cache.dispose);
      var notified = 0;
      cache.addListener(() => notified++);
      await cache.fetch(r'$a');

      decryption.keyArrives(encrypted, opens: opened());
      await pumpEventQueue();

      expect(cache.resolved(r'$a')?.body, 'hi');
      expect(await cache.fetch(r'$a'), same(cache.resolved(r'$a')));
      expect(notified, 1);
    });

    test('stays put when a key for another conversation arrives', () async {
      var lookups = 0;
      final cache = ReplyTargetCache((id) async {
        lookups++;
        return locked();
      });
      addTearDown(cache.dispose);
      var notified = 0;
      cache.addListener(() => notified++);
      await cache.fetch(r'$a');
      await pumpEventQueue();
      final attempts = decryption.attempts;

      decryption.keyArrives(encrypted, opens: opened(), sessionId: 'another');
      await pumpEventQueue();

      expect(lookups, 1);
      expect(decryption.attempts, attempts);
      expect(cache.resolved(r'$a')?.type, EventTypes.Encrypted);
      expect(notified, 0);
    });

    test('a readable target is never decrypted again', () async {
      final cache = ReplyTargetCache((id) async => opened());
      addTearDown(cache.dispose);
      await cache.fetch(r'$a');

      decryption.keyArrives(encrypted, opens: opened());
      await pumpEventQueue();

      expect(decryption.attempts, 0);
    });

    test('a key arriving after dispose announces nothing', () async {
      final cache = ReplyTargetCache((id) async => locked());
      var notified = 0;
      cache.addListener(() => notified++);
      await cache.fetch(r'$a');
      cache.dispose();

      decryption.keyArrives(encrypted, opens: opened());
      await pumpEventQueue();

      expect(notified, 0);
    });
  });
}
