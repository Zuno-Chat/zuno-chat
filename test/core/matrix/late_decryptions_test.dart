import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/late_decryptions.dart';

import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/test_clock.dart';

void main() {
  late FakeRoomDecryption decryption;
  late DecryptingTestClient client;
  late Room room;

  var now = DateTime(2026, 10, 28, 12);
  final clockedTest = testsOnClock(() => now);

  setUp(() {
    now = DateTime(2026, 10, 28, 12);
    decryption = FakeRoomDecryption();
    client = DecryptingTestClient(decryption);
    room = buildTestRoom(client);
  });

  Event locked({String eventId = r'$1', String? sessionId = 'session'}) =>
      lockedTestEvent(
        room,
        eventId: eventId,
        senderId: '@a:x',
        sessionId: sessionId,
      );

  Event opened({String eventId = r'$1'}) => buildTestEvent(
    room,
    eventId: eventId,
    senderId: '@a:x',
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
  );

  List<Event> collect(Stream<Event> events) {
    final seen = <Event>[];
    events.listen(seen.add);
    return seen;
  }

  group('the timeline', () {
    test('passes every event on as it comes', () async {
      final seen = collect(LateDecryptions.of(client).timeline);

      client.onTimelineEvent.add(opened());
      await pumpEventQueue();

      expect(seen.map((e) => e.body), ['hi']);
    });

    test(
      'announces a locked message again, opened, once its key arrives',
      () async {
        final late = LateDecryptions.of(client);
        final timeline = collect(late.timeline);
        final decrypted = collect(late.decrypted);
        client.onTimelineEvent.add(locked());
        await pumpEventQueue();

        decryption.keyArrives(room, opens: opened());
        await pumpEventQueue();

        expect(timeline.map((e) => e.type), [
          EventTypes.Encrypted,
          EventTypes.Message,
        ]);
        expect(decrypted.single.body, 'hi');
      },
    );

    test('a message deleted before its key arrives stays gone', () async {
      final late = LateDecryptions.of(client);
      final decrypted = collect(late.decrypted);
      client.onTimelineEvent.add(locked());
      await pumpEventQueue();

      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$redaction',
          senderId: '@a:x',
          type: EventTypes.Redaction,
          content: {'redacts': r'$1'},
        ),
      );
      decryption.keyArrives(room, opens: opened());
      await pumpEventQueue();

      expect(decrypted, isEmpty);
      expect(late.watches(r'$1'), isFalse);
    });

    test('a key for another conversation leaves it locked', () async {
      final decrypted = collect(LateDecryptions.of(client).decrypted);
      client.onTimelineEvent.add(locked());
      await pumpEventQueue();

      decryption.keyArrives(room, opens: opened(), sessionId: 'another');
      await pumpEventQueue();

      expect(decrypted, isEmpty);
      expect(decryption.attempts, 0);
    });

    test(
      'announces a message once, however often its key is announced',
      () async {
        final decrypted = collect(LateDecryptions.of(client).decrypted);
        client.onTimelineEvent.add(locked());
        await pumpEventQueue();

        decryption.keyArrives(room, opens: opened());
        await pumpEventQueue();
        decryption.keyArrives(room);
        await pumpEventQueue();

        expect(decrypted, hasLength(1));
        expect(decryption.attempts, 1);
      },
    );

    clockedTest('waits five minutes for a key, and no longer', () async {
      final late = LateDecryptions.of(client);
      final decrypted = collect(late.decrypted);
      client.onTimelineEvent.add(locked(eventId: r'$1'));
      client.onTimelineEvent.add(locked(eventId: r'$2'));
      await pumpEventQueue();

      now = now.add(const Duration(minutes: 5));
      decryption.keyArrives(room, opens: opened(eventId: r'$1'));
      await pumpEventQueue();
      expect(decrypted.map((e) => e.eventId), [r'$1']);

      now = now.add(const Duration(seconds: 1));
      decryption.keyArrives(room, opens: opened(eventId: r'$2'));
      await pumpEventQueue();
      expect(decrypted.map((e) => e.eventId), [r'$1']);
    });

    test(
      'watches at most 256 locked messages, forgetting the oldest',
      () async {
        LateDecryptions.of(client);
        for (var i = 0; i < 257; i++) {
          client.onTimelineEvent.add(locked(eventId: '\$$i'));
        }
        await pumpEventQueue();

        decryption.keyArrives(room);
        await pumpEventQueue();

        expect(decryption.attempts, 256);
      },
    );

    test('ignores a locked message with no session to wait on', () async {
      LateDecryptions.of(client);
      client.onTimelineEvent.add(locked(sessionId: null));
      await pumpEventQueue();

      decryption.keyArrives(room);
      await pumpEventQueue();

      expect(decryption.attempts, 0);
    });
  });

  test('there is one per client', () {
    expect(LateDecryptions.of(client), same(LateDecryptions.of(client)));
    expect(
      LateDecryptions.of(client),
      isNot(same(LateDecryptions.of(DecryptingTestClient(decryption)))),
    );
  });

  group('whether it watches an event', () {
    test('it does while the event waits for its key, and not once it '
        'opened', () async {
      final late = LateDecryptions.of(client);
      client.onTimelineEvent.add(locked());
      await pumpEventQueue();
      expect(late.watches(r'$1'), isTrue);

      decryption.keyArrives(room, opens: opened());
      await pumpEventQueue();

      expect(late.watches(r'$1'), isFalse);
    });

    clockedTest('it does not after five minutes', () async {
      final late = LateDecryptions.of(client);
      client.onTimelineEvent.add(locked());
      await pumpEventQueue();

      now = now.add(const Duration(minutes: 5, seconds: 1));

      expect(late.watches(r'$1'), isFalse);
    });
  });

  test('follows the room when the client replaces it', () async {
    final decrypted = collect(LateDecryptions.of(client).decrypted);
    client.onTimelineEvent.add(locked(eventId: r'$1'));
    await pumpEventQueue();
    final replaced = buildTestRoom(client);
    client.onTimelineEvent.add(
      lockedTestEvent(replaced, eventId: r'$2', senderId: '@a:x'),
    );
    await pumpEventQueue();

    decryption.keyArrives(replaced, opens: opened(eventId: r'$1'));
    await pumpEventQueue();

    expect(decrypted.map((e) => e.eventId), [r'$1']);
  });
}
