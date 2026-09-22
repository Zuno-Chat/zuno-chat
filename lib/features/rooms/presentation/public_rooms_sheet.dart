import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import 'room_kind_avatar.dart';

typedef PublicRoomsSearch = Future<QueryPublicRoomsResponse> Function({
  String? term,
  String? since,
});

const _searchDebounce = Duration(milliseconds: 300);
const _pageSize = 20;

Future<String?> showPublicRoomsSheet(
  BuildContext context, {
  required Client client,
  PublicRoomsSearch? search,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _PublicRoomsSheet(
    client: client,
    search: search ?? _directorySearch(client),
  ),
);

PublicRoomsSearch _directorySearch(Client client) =>
    ({term, since}) => client.queryPublicRooms(
      filter: term == null
          ? null
          : PublicRoomQueryFilter(genericSearchTerm: term),
      since: since,
      limit: _pageSize,
    );

String publicRoomTitle(PublishedRoomsChunk room) {
  final name = room.name;
  if (name != null && name.trim().isNotEmpty) return name;
  return withoutServer(room.canonicalAlias ?? room.roomId);
}

class _PublicRoomsSheet extends StatefulWidget {
  final Client client;
  final PublicRoomsSearch search;

  const _PublicRoomsSheet({required this.client, required this.search});

  @override
  State<_PublicRoomsSheet> createState() => _PublicRoomsSheetState();
}

class _PublicRoomsSheetState extends State<_PublicRoomsSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String? _term;
  int _generation = 0;

  var _rooms = <PublishedRoomsChunk>[];
  String? _nextBatch;
  var _loading = true;
  var _loadingMore = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      final trimmed = text.trim();
      final term = trimmed.isEmpty ? null : trimmed;
      if (term == _term) return;
      _term = term;
      _search();
    });
  }

  Future<void> _search() {
    setState(() {
      _loading = true;
      _failed = false;
      _rooms = [];
      _nextBatch = null;
    });
    return _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final page = await widget.search(term: _term);
      if (_isStale(generation)) return;
      setState(() {
        _rooms = _withoutSpaces(page.chunk);
        _nextBatch = page.nextBatch;
        _loading = false;
      });
    } catch (_) {
      if (_isStale(generation)) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final since = _nextBatch;
    if (since == null || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      final page = await widget.search(term: _term, since: since);
      if (_isStale(generation)) return;
      setState(() {
        _rooms = [..._rooms, ..._withoutSpaces(page.chunk)];
        _nextBatch = page.nextBatch;
      });
    } catch (_) {
      if (_isStale(generation)) return;
      setState(() => _nextBatch = null);
    } finally {
      _loadingMore = false;
    }
  }

  bool _isStale(int generation) => generation != _generation || !mounted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Public rooms',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofillHints: null,
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name or topic',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load rooms'),
            TextButton(onPressed: _search, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rooms.isEmpty) return const Center(child: Text('No rooms found'));

    final hasMore = _nextBatch != null;
    return ListView.builder(
      itemCount: _rooms.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _rooms.length) return _LoadMore(onVisible: _loadMore);
        final room = _rooms[index];
        return _RoomRow(
          client: widget.client,
          room: room,
          joined: _isJoined(room),
        );
      },
    );
  }

  bool _isJoined(PublishedRoomsChunk room) =>
      widget.client.getRoomById(room.roomId)?.membership == Membership.join;
}

class _RoomRow extends StatelessWidget {
  final Client client;
  final PublishedRoomsChunk room;
  final bool joined;

  const _RoomRow({
    required this.client,
    required this.room,
    required this.joined,
  });

  @override
  Widget build(BuildContext context) {
    final title = publicRoomTitle(room);
    final topic = room.topic?.trim();
    final hasTopic = topic != null && topic.isNotEmpty;
    return ListTile(
      leading: RoomKindAvatar(
        client: client,
        avatarUrl: room.avatarUrl,
        fallbackText: title,
        isDirect: false,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTopic)
            Text(topic, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(_memberCount(room.numJoinedMembers)),
        ],
      ),
      isThreeLine: hasTopic,
      trailing: joined ? const Text('Joined') : null,
      onTap: () => Navigator.of(context).pop(room.roomId),
    );
  }
}

List<PublishedRoomsChunk> _withoutSpaces(List<PublishedRoomsChunk> rooms) =>
    rooms.where((r) => r.roomType != 'm.space').toList();

String _memberCount(int count) => count == 1 ? '1 member' : '$count members';

class _LoadMore extends StatelessWidget {
  final VoidCallback onVisible;

  const _LoadMore({required this.onVisible});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onVisible());
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
