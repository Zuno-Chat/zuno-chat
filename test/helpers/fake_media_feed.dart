import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_media_feed.dart';

RoomMediaFeed fakeMediaFeed(
  Room room,
  Map<String?, RoomMediaBatch> pages, {
  int pageSize = 40,
  List<String?>? calls,
  Map<String?, Completer<void>> gates = const {},
}) {
  final feed = RoomMediaFeed(
    room,
    pageSize: pageSize,
    fetchPage: (cursor) async {
      calls?.add(cursor);
      await gates[cursor]?.future;
      final page = pages[cursor];
      if (page == null) throw StateError('offline');
      return page;
    },
  );
  addTearDown(feed.dispose);
  return feed;
}
