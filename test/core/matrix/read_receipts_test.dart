import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/read_receipts.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;
  late Event event;

  setUp(() {
    room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
    event = buildTestEvent(
      room,
      eventId: r'$msg',
      senderId: '@me:example.org',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    room.setState(User('@bob:example.org', displayName: 'Bob', room: room));
  });

  void receipts(Map<String, int> tsByUser) =>
      room.receiptState = LatestReceiptState(
        global: LatestReceiptStateForTimeline(
          ownPrivate: null,
          ownPublic: null,
          latestOwnReceipt: null,
          otherUsers: {
            for (final MapEntry(key: user, value: ts) in tsByUser.entries)
              user: LatestReceiptStateData('\$at-$ts', ts),
          },
        ),
      );

  test('not read when there are no receipts at all', () {
    expect(isReadByOthers(room, event), isFalse);
  });

  test('read once another user has a receipt at or after the event', () {
    receipts({'@bob:example.org': 2000});

    expect(isReadByOthers(room, event), isTrue);
  });

  test('not read when the other user\'s receipt is for an earlier event', () {
    receipts({'@bob:example.org': 500});

    expect(isReadByOthers(room, event), isFalse);
  });

  test('seenByOthers names who and when, sorted by receipt time', () {
    room.setState(User('@carol:example.org', displayName: 'Carol', room: room));
    receipts({'@bob:example.org': 3000, '@carol:example.org': 2000});

    final seenBy = seenByOthers(room, event);

    expect(seenBy.map((s) => s.user.calcDisplayname()).toList(), [
      'Carol',
      'Bob',
    ]);
  });

  group('read marker', () {
    late StoredEventsFakeDatabaseApi database;
    late Room stored;

    Event withStatus(String eventId, EventStatus status) => buildTestEvent(
      stored,
      eventId: eventId,
      senderId: '@bob:example.org',
      status: status,
    );

    setUp(() {
      database = StoredEventsFakeDatabaseApi();
      stored = buildTestRoom(
        buildTestClient(userId: '@me:example.org', database: database),
      );
    });

    test("only a server-accepted event carries it, since a local echo's id "
        'can still change', () {
      for (final (status, carries) in [
        (EventStatus.sending, false),
        (EventStatus.error, false),
        (EventStatus.sent, true),
        (EventStatus.synced, true),
      ]) {
        expect(
          canCarryReadMarker(withStatus(r'$e', status)),
          carries,
          reason: '$status',
        );
      }
    });

    test('an event the SDK made up locally never carries it, whatever its '
        'status, since the server rejects an id it never issued', () {
      expect(
        canCarryReadMarker(
          withStatus('test-1-1000_cancel_send', EventStatus.synced),
        ),
        isFalse,
      );
    });

    test(
      'the newest target is the last event when the server has it',
      () async {
        stored.lastEvent = withStatus(r'$last', EventStatus.synced);

        expect(await newestReadMarkerEventId(stored), r'$last');
      },
    );

    test('the newest target skips a made-up last event for the newest stored '
        'server event', () async {
      stored.lastEvent = withStatus(
        'test-2-1000_cancel_send',
        EventStatus.synced,
      );
      database.events = [
        withStatus('test-2-1000', EventStatus.error),
        withStatus('test-2-1000_cancel_send', EventStatus.synced),
        withStatus(r'$newest', EventStatus.synced),
        withStatus(r'$older', EventStatus.synced),
      ];

      expect(await newestReadMarkerEventId(stored), r'$newest');
    });

    test('there is no newest target when no event can carry it', () async {
      stored.lastEvent = withStatus('test-3-1000', EventStatus.error);
      database.events = [withStatus('test-3-1000', EventStatus.error)];

      expect(await newestReadMarkerEventId(stored), isNull);
    });
  });
}
