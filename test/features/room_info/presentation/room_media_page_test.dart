import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/gallery_viewer_page.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';
import 'package:zuno/features/room_info/presentation/room_media_page.dart';
import 'package:zuno/features/room_info/presentation/room_media_thumb.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  Event message(String id, DateTime ts, Map<String, Object?> content) =>
      buildTestEvent(
        room,
        eventId: id,
        senderId: '@a:example.org',
        content: content,
        originServerTs: ts,
      );

  Event image(String id, DateTime ts) => message(id, ts, {
    'msgtype': 'm.image',
    'body': 'a.jpg',
    'url': 'mxc://x/$id',
  });

  Event video(String id, DateTime ts, {required int durationMs}) =>
      message(id, ts, {
        'msgtype': 'm.video',
        'body': 'a.mp4',
        'url': 'mxc://x/$id',
        'info': {'duration': durationMs},
      });

  Event file(
    String id,
    DateTime ts, {
    required String name,
    required int size,
  }) => message(id, ts, {
    'msgtype': 'm.file',
    'body': name,
    'url': 'mxc://x/$id',
    'info': {'size': size},
  });

  Event text(String id) =>
      message(id, DateTime(2026, 9, 1), {'msgtype': 'm.text', 'body': 'hi'});

  RoomMediaFeed feedOf(List<Event> events) {
    final feed = RoomMediaFeed(
      room,
      fetchPage: (_) async => (events: events, nextBatch: null),
    );
    addTearDown(feed.dispose);
    return feed;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    RoomMediaFeed feed, {
    RoomMediaTab initialTab = RoomMediaTab.media,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roomMediaFeedProvider(room).overrideWithValue(feed)],
        child: MaterialApp(
          home: RoomMediaPage(room: room, initialTab: initialTab),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('groups photos and videos by month, newest first', (
    tester,
  ) async {
    final feed = feedOf([
      image(r'$1', DateTime(2026, 9, 14)),
      video(r'$2', DateTime(2026, 9, 2), durationMs: 42000),
      image(r'$3', DateTime(2026, 8, 30)),
    ]);
    await pumpPage(tester, feed);

    expect(find.byType(RoomMediaThumb), findsNWidgets(3));
    expect(find.text('0:42'), findsOneWidget);
    final september = tester.getTopLeft(find.text('September 2026'));
    final august = tester.getTopLeft(find.text('August 2026'));
    expect(september.dy, lessThan(august.dy));
  });

  testWidgets('opens the swipe viewer at the tapped item', (tester) async {
    final feed = feedOf([
      image(r'$1', DateTime(2026, 9, 14)),
      image(r'$2', DateTime(2026, 9, 13)),
      image(r'$3', DateTime(2026, 9, 12)),
    ]);
    await pumpPage(tester, feed);

    await tester.tap(find.byType(RoomMediaThumb).at(1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(GalleryViewerPage), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('lists files with size and date on the Files tab', (
    tester,
  ) async {
    final feed = feedOf([
      image(r'$1', DateTime(2026, 9, 14)),
      file(r'$f', DateTime(2026, 9, 14), name: 'report.pdf', size: 12595),
    ]);
    await pumpPage(tester, feed);
    expect(find.byType(RoomMediaThumb), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('report'), findsOneWidget);
    expect(find.text('.pdf'), findsOneWidget);
    expect(find.text('12.3 KB · 14 Sep 2026'), findsOneWidget);
    expect(find.byType(RoomMediaThumb), findsNothing);
  });

  testWidgets('keeps loading on its own while history yields media', (
    tester,
  ) async {
    final pages = <String?, RoomMediaBatch>{
      null: (events: [image(r'$1', DateTime(2026, 9, 3))], nextBatch: 'b1'),
      'b1': (events: [image(r'$2', DateTime(2026, 9, 2))], nextBatch: 'b2'),
      'b2': (events: [image(r'$3', DateTime(2026, 9, 1))], nextBatch: null),
    };
    final feed = RoomMediaFeed(
      room,
      pageSize: 1,
      fetchPage: (cursor) async => pages[cursor]!,
    );
    addTearDown(feed.dispose);
    await pumpPage(tester, feed);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(find.byType(RoomMediaThumb), findsNWidgets(3));
    expect(find.text('Load older'), findsNothing);
  });

  testWidgets('offers to load older after a dry stretch of history', (
    tester,
  ) async {
    final pages = <String?, RoomMediaBatch>{
      null: (events: [text(r'$t')], nextBatch: 'b1'),
      'b1': (events: [image(r'$1', DateTime(2026, 9, 1))], nextBatch: null),
    };
    final feed = RoomMediaFeed(
      room,
      maxRequestsPerLoad: 1,
      fetchPage: (cursor) async => pages[cursor]!,
    );
    addTearDown(feed.dispose);
    await pumpPage(tester, feed);

    expect(find.byType(RoomMediaThumb), findsNothing);
    expect(find.text('Load older'), findsOneWidget);

    await tester.tap(find.text('Load older'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.byType(RoomMediaThumb), findsOneWidget);
    expect(find.text('Load older'), findsNothing);
  });

  testWidgets('offers to try again after a failed load', (tester) async {
    var attempts = 0;
    final feed = RoomMediaFeed(
      room,
      fetchPage: (_) async {
        if (++attempts == 1) throw StateError('offline');
        return (events: [image(r'$1', DateTime(2026, 9, 1))], nextBatch: null);
      },
    );
    addTearDown(feed.dispose);
    await pumpPage(tester, feed);

    expect(find.text('Could not load media.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.byType(RoomMediaThumb), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('keeps the last row clear of the bottom system inset', (
    tester,
  ) async {
    final feed = feedOf([
      for (var i = 0; i < 30; i++) image('\$$i', DateTime(2026, 9, 14)),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [roomMediaFeedProvider(room).overrideWithValue(feed)],
        child: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 100)),
          child: MaterialApp(home: RoomMediaPage(room: room)),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    await tester.fling(
      find.byType(CustomScrollView).first,
      const Offset(0, -5000),
      3000,
    );
    await tester.pumpAndSettle();

    final lastThumb = tester.getBottomLeft(find.byType(RoomMediaThumb).last);
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(lastThumb.dy, lessThanOrEqualTo(screen.height - 100));
  });

  testWidgets('shows empty states once history is exhausted', (tester) async {
    await pumpPage(tester, feedOf([]));

    expect(find.text('No photos or videos yet.'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('No files yet.'), findsOneWidget);
  });
}
