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
}
