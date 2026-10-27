import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/room_media_feed.dart';

typedef ViewerGallery = ({Event message, List<Event> members});

class ViewerItems extends ChangeNotifier {
  final RoomMediaFeed _feed;
  final Event _opened;
  List<Event> _items;
  bool _reached = false;
  bool _started = false;
  bool _searchDone = false;
  bool _disposed = false;
  bool _couldLoadOlder = false;

  ViewerItems(this._feed, {required Event opened})
    : _opened = opened,
      _items = UnmodifiableListView([opened]) {
    _feed.addListener(_follow);
    _follow();
  }

  List<Event> get items => _items;

  bool get canLoadOlder => _feed.canAutoLoad;

  void start() {
    if (_started) return;
    _started = true;
    if (_reached) {
      _searchDone = true;
      return;
    }
    unawaited(_reachOpened());
  }

  Future<void> loadOlder() async {
    if (!canLoadOlder) return;
    await runBestEffort(_feed.loadMore, label: 'viewer load older');
  }

  Future<void> retryOlder() async {
    if (!_feed.hasMore || _feed.loading) return;
    await runBestEffort(_feed.loadMore, label: 'viewer retry older');
  }

  ViewerGallery? galleryOf(Event item) {
    if (galleryGroupOf(item) == null) return null;
    final grouping = groupGalleries(_items.reversed.toList());
    for (final MapEntry(key: anchorId, value: members)
        in grouping.galleries.entries) {
      if (!members.any((e) => e.eventId == item.eventId)) continue;
      final message = members.firstWhere((e) => e.eventId == anchorId);
      return (message: message, members: members);
    }
    return null;
  }

  Future<void> _reachOpened() async {
    await runBestEffort(
      () => _feed.loadThrough(_opened.originServerTs),
      label: 'viewer reach opened',
    );
    if (_disposed) return;
    _searchDone = true;
    _follow();
  }

  void _follow() {
    final visuals = _feed.visuals;
    if (!_reached && visuals.any((e) => e.eventId == _opened.eventId)) {
      _reached = true;
    }
    final openedGone = _feed.wasRedacted(_opened.eventId);
    final List<Event> next;
    if (_reached) {
      next = visuals.reversed.toList();
    } else if (_searchDone) {
      next = [...visuals, if (!openedGone) _opened]
        ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    } else {
      next = [if (!openedGone) _opened];
    }
    final canLoad = canLoadOlder;
    final sameItems = listEquals(
      [for (final event in next) event.eventId],
      [for (final event in _items) event.eventId],
    );
    if (sameItems && canLoad == _couldLoadOlder) return;
    if (!sameItems) _items = UnmodifiableListView(next);
    _couldLoadOlder = canLoad;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _feed.removeListener(_follow);
    super.dispose();
  }
}
