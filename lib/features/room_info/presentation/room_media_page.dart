import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/attachment_actions.dart';
import '../../../core/matrix/attachment_feedback.dart';
import '../../../core/matrix/media_size.dart';
import '../../../core/matrix/room_media_feed.dart';
import '../../../core/ui/failure_notice.dart';
import '../../../core/ui/load_more_trigger.dart';
import '../../chat/presentation/file_name_text.dart';
import '../../chat/presentation/media_viewer/media_viewer_page.dart';
import 'room_media_thumb.dart';

enum RoomMediaTab { media, files }

Future<void> loadRoomMedia(Future<void> Function() load) =>
    runBestEffort(load, label: 'loadRoomMedia');

class RoomMediaPage extends ConsumerStatefulWidget {
  final ViewerChat viewerChat;
  final RoomMediaTab initialTab;

  const RoomMediaPage({
    required this.viewerChat,
    this.initialTab = RoomMediaTab.media,
    super.key,
  });

  @override
  ConsumerState<RoomMediaPage> createState() => _RoomMediaPageState();
}

class _RoomMediaPageState extends ConsumerState<RoomMediaPage> {
  late final RoomMediaFeed _feed = ref.read(
    roomMediaFeedProvider(widget.viewerChat.room),
  );

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
          title: Text(context.l10n.roomInfoMedia),
          bottom: TabBar(
            tabs: [
              Tab(text: context.l10n.roomInfoPhotosAndVideos),
              Tab(text: context.l10n.roomInfoFiles),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: _feed,
          builder: (context, _) => TabBarView(
            children: [
              _MediaGrid(feed: _feed, viewerChat: widget.viewerChat),
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
  final events = <Event>[];

  _MonthGroup(this.label);
}

List<_MonthGroup> _byMonth(List<Event> events, DateLabels labels) {
  final groups = <_MonthGroup>[];
  for (final event in events) {
    final label = labels.month(event.originServerTs);
    if (groups.isEmpty || groups.last.label != label) {
      groups.add(_MonthGroup(label));
    }
    groups.last.events.add(event);
  }
  return groups;
}

class _MediaGrid extends StatelessWidget {
  final RoomMediaFeed feed;
  final ViewerChat viewerChat;

  const _MediaGrid({required this.feed, required this.viewerChat});

  @override
  Widget build(BuildContext context) {
    final visuals = feed.visuals;
    return CustomScrollView(
      slivers: [
        for (final month in _byMonth(visuals, DateLabels.of(context))) ...[
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
                onTap: () => openMediaViewer(
                  context,
                  chat: viewerChat,
                  opened: month.events[i],
                ),
              ),
            ),
          ),
        ],
        _LoadFooter(
          feed: feed,
          isEmpty: visuals.isEmpty,
          emptyText: context.l10n.roomInfoNoPhotosOrVideos,
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
    final labels = DateLabels.of(context);
    return CustomScrollView(
      slivers: [
        SliverList.builder(
          itemCount: files.length,
          itemBuilder: (context, i) =>
              _FileRow(event: files[i], labels: labels),
        ),
        _LoadFooter(
          feed: feed,
          isEmpty: files.isEmpty,
          emptyText: context.l10n.roomInfoNoFiles,
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final Event event;
  final DateLabels labels;

  const _FileRow({required this.event, required this.labels});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = event.fileSize;
    final details = joinDetails([
      if (size != null) formatBytes(l10n, size),
      labels.date(event.originServerTs),
    ]);
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: FileNameText(attachmentFileName(event)),
      subtitle: Text(details),
      trailing: IconButton(
        icon: const Icon(Icons.share_outlined),
        tooltip: l10n.commonShare,
        onPressed: () => shareAttachmentsWithFeedback(
          ScaffoldMessenger.of(context),
          l10n,
          [event],
        ),
      ),
      onTap: () => saveAttachmentsWithFeedback(
        ScaffoldMessenger.of(context),
        l10n,
        [event],
      ),
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

  Widget _stalledContent(BuildContext context) {
    final l10n = context.l10n;
    void loadMore() => loadRoomMedia(feed.loadMore);
    if (feed.failed) {
      return FailureNotice(
        message: l10n.roomInfoCouldNotLoadMedia,
        onRetry: loadMore,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.roomInfoNothingRecent),
          ),
        TextButton(onPressed: loadMore, child: Text(l10n.roomInfoLoadOlder)),
      ],
    );
  }

  Widget? _content(BuildContext context) {
    if (feed.loading) return const CircularProgressIndicator();
    if (!feed.hasMore) return isEmpty ? Text(emptyText) : null;
    if (feed.stalled) return _stalledContent(context);
    return LoadMoreTrigger(
      key: ValueKey(feed.items.length),
      onVisible: () => unawaited(loadRoomMedia(feed.loadMore)),
    );
  }

  Widget _sliver(BuildContext context) {
    final content = _content(context);
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
      SliverSafeArea(top: false, sliver: _sliver(context));
}
