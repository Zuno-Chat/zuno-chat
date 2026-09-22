import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';

void main() {
  test('no pending send: never shows the synthetic tile', () {
    expect(
      pendingSendNeedsSyntheticTile(
        pendingEventId: null,
        timelineEventIds: ['a', 'b'],
      ),
      isFalse,
    );
  });

  test('pending send not yet in the timeline: shows the synthetic tile', () {
    expect(
      pendingSendNeedsSyntheticTile(
        pendingEventId: 'txid-1',
        timelineEventIds: ['a', 'b'],
      ),
      isTrue,
    );
  });

  test(
    'pending send already represented by a real event: no synthetic tile',
    () {
      expect(
        pendingSendNeedsSyntheticTile(
          pendingEventId: 'txid-1',
          timelineEventIds: ['a', 'txid-1', 'b'],
        ),
        isFalse,
      );
    },
  );

  test('empty timeline with a pending send: shows the synthetic tile', () {
    expect(
      pendingSendNeedsSyntheticTile(
        pendingEventId: 'txid-1',
        timelineEventIds: const [],
      ),
      isTrue,
    );
  });
}
