import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import 'communities.dart';

typedef CommunityRoomsPageLoader = Future<GetSpaceHierarchyResponse> Function(
  Room community, {
  String? from,
});

const _pageSize = 20;

Future<GetSpaceHierarchyResponse> communityRoomsPage(
  Room community, {
  String? from,
}) => community.client.getSpaceHierarchy(
  community.id,
  maxDepth: 1,
  limit: _pageSize,
  from: from,
);

class JoinableRoomsFeed extends ChangeNotifier {
  final Room community;
  final CommunityRoomsPageLoader _loadPage;

  List<SpaceRoomsChunk$2>? _chunks;
  final _ids = <String>{};
  String? _next;
  bool _ended = false;
  bool _loading = false;
  bool _failed = false;
  bool _failedAtStart = false;
  int _generation = 0;
  bool _disposed = false;

  JoinableRoomsFeed(this.community, {required this._loadPage});

  Client get _client => community.client;

  List<SpaceRoomsChunk$2>? get rooms => _chunks?.where(_unjoined).toList();
  bool get loading => _loading;
  bool get failed => _failed;
  bool get hasMore => !_ended;

  Future<void> refresh() => _run(fromStart: true);

  Future<void> loadMore() async {
    if (_loading || _failed || _ended || _chunks == null) return;
    await _run(fromStart: false);
  }

  Future<void> retry() => _run(fromStart: _failedAtStart);

  bool _unjoined(SpaceRoomsChunk$2 chunk) =>
      _client.getRoomById(chunk.roomId)?.membership != Membership.join;

  bool get _listsUnjoined =>
      communityChildIds(community)
          .any((id) => _client.getRoomById(id)?.membership != Membership.join);

  static bool _forgotten(MatrixException e, String? from) =>
      from != null && e.error == MatrixError.M_INVALID_PARAM;

  Future<void> _run({required bool fromStart}) async {
    final generation = ++_generation;
    bool stale() => generation != _generation || _disposed;
    _loading = true;
    _failed = false;
    notifyListeners();
    var atStart = fromStart;
    var from = fromStart ? null : _next;
    var restarted = false;
    try {
      while (true) {
        if (!_listsUnjoined) {
          _land(const [], next: null, replace: atStart);
          return;
        }
        final GetSpaceHierarchyResponse page;
        try {
          page = await _loadPage(community, from: from);
        } on MatrixException catch (e) {
          if (restarted || !_forgotten(e, from)) rethrow;
          if (stale()) return;
          restarted = true;
          from = null;
          continue;
        }
        if (stale()) return;
        final added = _land(page.rooms, next: page.nextBatch, replace: atStart);
        atStart = false;
        from = page.nextBatch;
        if (added > 0 || _ended) return;
      }
    } catch (e, s) {
      if (stale()) return;
      reportCaught('community rooms', e, s);
      _failed = true;
      _failedAtStart = atStart;
    } finally {
      if (!stale()) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  int _land(
    List<SpaceRoomsChunk$2> page, {
    required String? next,
    required bool replace,
  }) {
    if (replace) {
      _chunks = [];
      _ids.clear();
    }
    final chunks = _chunks ??= [];
    _next = next;
    _ended = next == null;
    var added = 0;
    for (final chunk in page) {
      if (chunk.roomId == community.id ||
          chunk.roomType == RoomCreationTypes.mSpace ||
          !_ids.add(chunk.roomId)) {
        continue;
      }
      chunks.add(chunk);
      if (_unjoined(chunk)) added++;
    }
    return added;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
