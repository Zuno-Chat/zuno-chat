import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/room_media_feed.dart';
import '../../../core/ui/card_group.dart';
import 'room_media_page.dart';
import 'room_media_thumb.dart';

const _previewCount = 6;

class RoomMediaSection extends ConsumerStatefulWidget {
  final Room room;

  const RoomMediaSection({required this.room, super.key});

  @override
  ConsumerState<RoomMediaSection> createState() => _RoomMediaSectionState();
}

class _RoomMediaSectionState extends ConsumerState<RoomMediaSection> {
  late final RoomMediaFeed _feed = ref.read(roomMediaFeedProvider(widget.room));

  @override
  void initState() {
    super.initState();
    unawaited(loadRoomMedia(_feed.ensureLoaded));
  }

  void _openAll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RoomMediaPage(room: widget.room)),
    );
  }

  Widget _body(BuildContext context) {
    final visuals = _feed.visuals;
    final total = _feed.items.length;
    if (visuals.isEmpty && _feed.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (total == 0 && !_feed.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('No media shared yet.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visuals.isNotEmpty)
          _PreviewGrid(
            events: visuals.take(_previewCount).toList(),
            onOpen: (i) => openRoomMediaViewer(context, visuals, i),
          ),
        _CountTile(
          icon: Icons.perm_media_outlined,
          title: 'More media and files',
          count: total == 0 ? null : '$total${_feed.hasMore ? '+' : ''}',
          onTap: _openAll,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _feed,
      builder: (context, _) =>
          CardGroup(title: 'Media', children: [_body(context)]),
    );
  }
}

class _PreviewGrid extends StatelessWidget {
  final List<Event> events;
  final void Function(int index) onOpen;

  const _PreviewGrid({required this.events, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: events.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemBuilder: (context, i) =>
            RoomMediaThumb(event: events[i], onTap: () => onOpen(i)),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? count;
  final VoidCallback onTap;

  const _CountTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = this.count;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null)
            Text(
              count,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
