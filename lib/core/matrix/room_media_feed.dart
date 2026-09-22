import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import 'event_display.dart';

enum RoomMediaKind { photo, video, file }

RoomMediaKind? roomMediaKindOf(Event event) {
  if (event.redacted ||
      !event.status.isSent ||
      event.relationshipType == RelationshipTypes.edit) {
    return null;
  }
  return switch (summarize(event).kind) {
    MessageKind.photo => RoomMediaKind.photo,
    MessageKind.video => RoomMediaKind.video,
    MessageKind.file => RoomMediaKind.file,
    _ => null,
  };
}

typedef RoomMediaBatch = ({List<Event> events, String? nextBatch});
typedef RoomMediaBatchFetcher = Future<RoomMediaBatch> Function(
  String? nextBatch,
);

const _eventsPerRequest = 100;

class RoomMediaFeed extends ChangeNotifier {
  final Room room;
  final int pageSize;
  final int maxRequestsPerLoad;
  final RoomMediaBatchFetcher _fetchPage;

  final _items = <Event>[];
  final _kinds = <String, RoomMediaKind>{};
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _stalled = false;
  bool _failed = false;
  Future<void>? _inFlight;
  late final StreamSubscription<Event> _syncSub;

  RoomMediaFeed(
    this.room, {
    RoomMediaBatchFetcher? fetchPage,
    this.pageSize = 40,
    this.maxRequestsPerLoad = 4,
  }) : _fetchPage = fetchPage ?? _searchHistory(room) {
    _syncSub = room.client.onTimelineEvent.stream.listen(_onTimelineEvent);
  }

  static RoomMediaBatchFetcher _searchHistory(Room room) => (cursor) async {
    final result = await room.searchEvents(
      searchFunc: (event) => roomMediaKindOf(event) != null,
      nextBatch: cursor,
      limit: _eventsPerRequest,
    );
    return (events: result.events, nextBatch: result.nextBatch);
  };

  List<Event> get items => List.unmodifiable(_items);

  List<Event> get visuals => [
    for (final event in _items)
      if (_kinds[event.eventId] != RoomMediaKind.file) event,
  ];

  List<Event> get files => [
    for (final event in _items)
      if (_kinds[event.eventId] == RoomMediaKind.file) event,
  ];

  bool get hasMore => _hasMore;
  bool get loading => _loading;
  bool get stalled => _stalled;
  bool get failed => _failed;

  Future<void> ensureLoaded() {
    if (_items.isNotEmpty || _loading || !_hasMore || _stalled) {
      return Future.value();
    }
    return loadMore();
  }

  Future<void> loadMore() =>
      _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    if (!_hasMore) return;
    _loading = true;
    notifyListeners();
    var added = 0;
    _failed = false;
    try {
      for (
        var requests = 0;
        requests < maxRequestsPerLoad && _hasMore && added < pageSize;
        requests++
      ) {
        final batch = await _fetchPage(_cursor);
        added += _add(batch.events);
        _cursor = batch.nextBatch;
        if (_cursor == null) _hasMore = false;
      }
      _stalled = added == 0;
    } catch (_) {
      _stalled = true;
      _failed = true;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  int _add(Iterable<Event> events, {bool atFront = false}) {
    var added = 0;
    for (final event in events) {
      final kind = roomMediaKindOf(event);
      if (kind == null || _kinds.containsKey(event.eventId)) continue;
      _kinds[event.eventId] = kind;
      if (atFront) {
        _items.insert(added, event);
      } else {
        _items.add(event);
      }
      added++;
    }
    return added;
  }

  void _onTimelineEvent(Event event) {
    if (event.room.id != room.id) return;
    if (event.type == EventTypes.Redaction) {
      final target = event.redacts ?? event.content.tryGet<String>('redacts');
      if (_kinds.remove(target) == null) return;
      _items.removeWhere((e) => e.eventId == target);
      notifyListeners();
      return;
    }
    if (_add([event], atFront: true) > 0) notifyListeners();
  }

  @override
  void dispose() {
    _syncSub.cancel();
    super.dispose();
  }
}

final roomMediaFeedProvider = Provider.family<RoomMediaFeed, Room>((ref, room) {
  ref.keepAlive();
  final feed = RoomMediaFeed(room);
  final logoutSub = room.client.onLoginStateChanged.stream
      .where((state) => state == LoginState.loggedOut)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() {
    logoutSub.cancel();
    feed.dispose();
  });
  return feed;
});
