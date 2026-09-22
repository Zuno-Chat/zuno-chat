import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/format/human_units.dart';
import '../../../core/matrix/attachment_action_buttons.dart';
import '../../../core/matrix/attachment_actions.dart';
import '../../../core/matrix/gallery_viewer_page.dart';
import '../../../core/matrix/room_media_feed.dart';
import '../../chat/presentation/file_name_text.dart';
import 'room_media_thumb.dart';

enum RoomMediaTab { media, files }

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthLabel(DateTime date) => '${_months[date.month - 1]} ${date.year}';

String _dayLabel(DateTime date) =>
    '${date.day} ${_months[date.month - 1].substring(0, 3)} ${date.year}';

Future<void> loadRoomMedia(Future<void> Function() load) =>
    runBestEffort(load, label: 'loadRoomMedia');

void openRoomMediaViewer(BuildContext context, List<Event> events, int index) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GalleryViewerPage(events: events, initialIndex: index),
    ),
  );
}

class RoomMediaPage extends ConsumerStatefulWidget {
  final Room room;
  final RoomMediaTab initialTab;

  const RoomMediaPage({
    required this.room,
    this.initialTab = RoomMediaTab.media,
    super.key,
  });

  @override
  ConsumerState<RoomMediaPage> createState() => _RoomMediaPageState();
}

class _RoomMediaPageState extends ConsumerState<RoomMediaPage> {
  late final RoomMediaFeed _feed = ref.read(roomMediaFeedProvider(widget.room));

  @override
  void initState() {
    super.initState();
    unawaited(loadRoomMedia(_feed.ensureLoaded));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: RoomMediaTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Photos and videos'),
              Tab(text: 'Files'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: _feed,
          builder: (context, _) => TabBarView(
            children: [
              _MediaGrid(feed: _feed),
              _FileList(feed: _feed),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGroup {
  final String label;
  final int offset;
  final events = <Event>[];

  _MonthGroup(this.label, this.offset);
}

List<_MonthGroup> _byMonth(List<Event> events) {
  final groups = <_MonthGroup>[];
  for (final (i, event) in events.indexed) {
    final label = _monthLabel(event.originServerTs.toLocal());
    if (groups.isEmpty || groups.last.label != label) {
      groups.add(_MonthGroup(label, i));
    }
    groups.last.events.add(event);
  }
  return groups;
}

class _MediaGrid extends StatelessWidget {
  final RoomMediaFeed feed;

  const _MediaGrid({required this.feed});

  @override
  Widget build(BuildContext context) {
    final visuals = feed.visuals;
    return CustomScrollView(
      slivers: [
        for (final month in _byMonth(visuals)) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                month.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: month.events.length,
              itemBuilder: (context, i) => RoomMediaThumb(
                event: month.events[i],
                onTap: () =>
                    openRoomMediaViewer(context, visuals, month.offset + i),
              ),
            ),
          ),
        ],
        _LoadFooter(
          feed: feed,
          isEmpty: visuals.isEmpty,
          emptyText: 'No photos or videos yet.',
        ),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  final RoomMediaFeed feed;

  const _FileList({required this.feed});

  @override
  Widget build(BuildContext context) {
    final files = feed.files;
    return CustomScrollView(
      slivers: [
        SliverList.builder(
          itemCount: files.length,
          itemBuilder: (context, i) => _FileRow(event: files[i]),
        ),
        _LoadFooter(
          feed: feed,
          isEmpty: files.isEmpty,
          emptyText: 'No files yet.',
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final Event event;

  const _FileRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final size = event.infoMap.tryGet<int>('size');
    final details = [
      if (size != null) formatBytes(size),
      _dayLabel(event.originServerTs.toLocal()),
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: FileNameText(attachmentFileName(event)),
      subtitle: Text(details),
      trailing: IconButton(
        icon: const Icon(Icons.share_outlined),
        tooltip: 'Share',
        onPressed: () => shareAttachmentsWithFeedback(
          ScaffoldMessenger.of(context),
          [event],
        ),
      ),
      onTap: () =>
          saveAttachmentWithFeedback(ScaffoldMessenger.of(context), event),
    );
  }
}

class _LoadFooter extends StatelessWidget {
  final RoomMediaFeed feed;
  final bool isEmpty;
  final String emptyText;

  const _LoadFooter({
    required this.feed,
    required this.isEmpty,
    required this.emptyText,
  });

  String? _stalledMessage() {
    if (feed.failed) return 'Could not load media.';
    if (isEmpty) return 'Nothing in recent messages.';
    return null;
  }

  Widget _stalledContent() {
    final message = _stalledMessage();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(message),
          ),
        TextButton(
          onPressed: () => loadRoomMedia(feed.loadMore),
          child: Text(feed.failed ? 'Try again' : 'Load older'),
        ),
      ],
    );
  }

  Widget? _content() {
    if (feed.loading) return const CircularProgressIndicator();
    if (!feed.hasMore) return isEmpty ? Text(emptyText) : null;
    if (feed.stalled) return _stalledContent();
    return _AutoLoad(key: ValueKey(feed.items.length), feed: feed);
  }

  Widget _sliver() {
    final content = _content();
    if (isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: content),
      );
    }
    if (content == null) return const SliverToBoxAdapter();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      SliverSafeArea(top: false, sliver: _sliver());
}

class _AutoLoad extends StatefulWidget {
  final RoomMediaFeed feed;

  const _AutoLoad({required this.feed, super.key});

  @override
  State<_AutoLoad> createState() => _AutoLoadState();
}

class _AutoLoadState extends State<_AutoLoad> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(loadRoomMedia(widget.feed.loadMore));
    });
  }

  @override
  Widget build(BuildContext context) => const CircularProgressIndicator();
}
