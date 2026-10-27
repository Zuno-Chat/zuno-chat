import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';
import 'package:zuno/features/chat/data/viewer_items.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_media_feed.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  Event media(
    String id, {
    required int ts,
    String msgtype = 'm.image',
    Map<String, Object?> extra = const {},
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: '@a:example.org',
    type: EventTypes.Message,
    content: {'msgtype': msgtype, 'body': 'a', 'url': 'mxc://x/$id', ...extra},
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
  );

  RoomMediaFeed feedOver(
    Map<String?, RoomMediaBatch> pages, {
    int pageSize = 40,
    List<String?>? calls,
    Completer<void>? gate,
  }) => fakeMediaFeed(
    room,
    pages,
    pageSize: pageSize,
    calls: calls,
    gates: {null: ?gate},
  );

  ViewerItems itemsOver(RoomMediaFeed feed, Event opened) {
    final items = ViewerItems(feed, opened: opened)..start();
    addTearDown(items.dispose);
    return items;
  }

  List<String> ids(ViewerItems items) =>
      items.items.map((e) => e.eventId).toList();

  test("lists the room's photos and videos oldest first", () async {
    final i1 = media(r'$i1', ts: 1);
    final feed = feedOver({
      null: (
        events: [
          media(r'$v3', ts: 3, msgtype: 'm.video'),
          media(r'$f', ts: 2, msgtype: 'm.file'),
          media(r'$i2', ts: 2),
          i1,
        ],
        nextBatch: null,
      ),
    });

    final items = itemsOver(feed, i1);
    await pumpEventQueue();

    expect(ids(items), [r'$i1', r'$i2', r'$v3']);
  });

  test('shows only the opened item until the feed reaches it', () async {
    final opened = media(r'$1', ts: 1);
    final gate = Completer<void>();
    final calls = <String?>[];
    final feed = feedOver(
      {
        null: (events: [media(r'$3', ts: 3)], nextBatch: 'b1'),
        'b1': (events: [media(r'$2', ts: 2), opened], nextBatch: null),
      },
      pageSize: 1,
      calls: calls,
      gate: gate,
    );

    final items = itemsOver(feed, opened);
    expect(ids(items), [r'$1']);

    gate.complete();
    await pumpEventQueue();

    expect(calls, [null, 'b1']);
    expect(ids(items), [r'$1', r'$2', r'$3']);
  });

  test('an opened item the feed never returns still shows among the rest by '
      'time', () async {
    final opened = media(r'$2', ts: 2);
    final feed = feedOver({
      null: (
        events: [media(r'$3', ts: 3), media(r'$1', ts: 1)],
        nextBatch: null,
      ),
    });

    final items = itemsOver(feed, opened);
    await pumpEventQueue();

    expect(ids(items), [r'$1', r'$2', r'$3']);
  });

  test('a new photo joins at the newest end', () async {
    final opened = media(r'$1', ts: 1);
    final feed = feedOver({
      null: (events: [opened], nextBatch: null),
    });
    final items = itemsOver(feed, opened);
    await pumpEventQueue();
    var notified = 0;
    items.addListener(() => notified++);

    client.onTimelineEvent.add(media(r'$new', ts: 9));
    await pumpEventQueue();

    expect(ids(items), [r'$1', r'$new']);
    expect(notified, greaterThan(0));
  });

  test('a deleted photo leaves the list', () async {
    final opened = media(r'$1', ts: 1);
    final feed = feedOver({
      null: (events: [media(r'$2', ts: 2), opened], nextBatch: null),
    });
    final items = itemsOver(feed, opened);
    await pumpEventQueue();

    client.onTimelineEvent.add(buildTestRedaction(room, r'$2'));
    await pumpEventQueue();

    expect(ids(items), [r'$1']);
  });

  test("galleryOf gives the gallery's members in order and its newest member "
      'as the message', () async {
    Map<String, Object?> slot(int index) =>
        galleryGroupContent(id: 'g', index: index, count: 3);
    final first = media(r'$g0', ts: 5, extra: slot(0));
    final feed = feedOver({
      null: (
        events: [
          media(r'$g1', ts: 7, extra: slot(1)),
          media(r'$g2', ts: 6, extra: slot(2)),
          first,
          media(r'$plain', ts: 1),
        ],
        nextBatch: null,
      ),
    });
    final items = itemsOver(feed, first);
    await pumpEventQueue();

    final gallery = items.galleryOf(first)!;
    expect(gallery.members.map((e) => e.eventId), [r'$g0', r'$g1', r'$g2']);
    expect(gallery.message.eventId, r'$g1');
    expect(items.galleryOf(items.items.first), isNull);
  });

  test('tells its listeners when it can load older items again', () async {
    final opened = media(r'$2', ts: 2);
    final feed = feedOver({
      null: (events: [opened], nextBatch: 'b1'),
      'b1': (events: [media(r'$1', ts: 1)], nextBatch: null),
    }, pageSize: 1);
    final items = itemsOver(feed, opened);
    final seen = <bool>[];
    items.addListener(() => seen.add(items.canLoadOlder));

    await pumpEventQueue();

    expect(ids(items), [r'$2']);
    expect(seen, contains(true));
  });

  test('loadOlder asks the feed for more only when it can', () async {
    final opened = media(r'$2', ts: 2);
    final calls = <String?>[];
    final feed = feedOver(
      {
        null: (events: [opened], nextBatch: 'b1'),
        'b1': (events: [media(r'$1', ts: 1)], nextBatch: null),
      },
      pageSize: 1,
      calls: calls,
    );
    final items = itemsOver(feed, opened);
    await pumpEventQueue();
    expect(items.canLoadOlder, isTrue);

    await items.loadOlder();
    expect(ids(items), [r'$1', r'$2']);
    expect(items.canLoadOlder, isFalse);

    await items.loadOlder();
    expect(calls, [null, 'b1']);
  });

  test(
    'after a failed load it does not ask for older items on its own',
    () async {
      final opened = media(r'$2', ts: 2);
      final calls = <String?>[];
      final feed = feedOver(
        {
          null: (events: [opened], nextBatch: 'b1'),
        },
        pageSize: 1,
        calls: calls,
      );
      final items = itemsOver(feed, opened);
      await pumpEventQueue();
      expect(items.canLoadOlder, isTrue);

      await items.loadOlder();
      await pumpEventQueue();

      expect(calls, [null, 'b1']);
      expect(items.canLoadOlder, isFalse);
    },
  );

  test('retryOlder tries again after a failed load', () async {
    final opened = media(r'$2', ts: 2);
    final calls = <String?>[];
    final feed = feedOver(
      {
        null: (events: [opened], nextBatch: 'b1'),
      },
      pageSize: 1,
      calls: calls,
    );
    final items = itemsOver(feed, opened);
    await pumpEventQueue();
    await items.loadOlder();
    await pumpEventQueue();

    await items.retryOlder();

    expect(calls, [null, 'b1', 'b1']);
  });

  test(
    'stops looking for the opened item once the feed is older than it',
    () async {
      final opened = media(r'$opened', ts: 5);
      final calls = <String?>[];
      final feed = feedOver(
        {
          null: (events: [media(r'$9', ts: 9)], nextBatch: 'b1'),
          'b1': (events: [media(r'$3', ts: 3)], nextBatch: 'b2'),
          'b2': (events: [media(r'$1', ts: 1)], nextBatch: null),
        },
        pageSize: 1,
        calls: calls,
      );

      final items = itemsOver(feed, opened);
      await pumpEventQueue();

      expect(calls, [null, 'b1']);
      expect(ids(items), [r'$3', r'$opened', r'$9']);
    },
  );

  test(
    'an opened item the feed never held leaves when it is deleted',
    () async {
      final opened = media(r'$2', ts: 2);
      final feed = feedOver({
        null: (
          events: [media(r'$3', ts: 3), media(r'$1', ts: 1)],
          nextBatch: null,
        ),
      });
      final items = itemsOver(feed, opened);
      await pumpEventQueue();
      expect(ids(items), [r'$1', r'$2', r'$3']);

      client.onTimelineEvent.add(buildTestRedaction(room, r'$2'));
      await pumpEventQueue();

      expect(ids(items), [r'$1', r'$3']);
    },
  );
}
