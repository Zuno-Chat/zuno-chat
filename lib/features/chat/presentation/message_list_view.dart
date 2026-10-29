import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/room_changes.dart';
import '../../../core/matrix/room_updates.dart';
import '../../../core/ui/inline_feedback.dart';
import '../../../core/ui/row_memo.dart';
import '../data/message_row_data.dart';
import '../data/pending_attachment_send.dart';
import 'date_divider.dart';
import 'empty_room_notice.dart';
import 'message_contents/pending_attachment_tile.dart';
import 'message_tile.dart';
import 'reply_target_cache.dart';
import 'room_update_tile.dart';

class MessageListView extends StatefulWidget {
  final Room room;
  final ValueListenable<Timeline?> timeline;
  final ScrollController controller;
  final bool showHiddenMessages;
  final bool canRespond;
  final List<FailedMediaSend> failedSends;
  final ValueListenable<PendingAttachmentSend?> pendingSend;
  final ReplyTargetCache replyTargets;
  final void Function(Event event, List<Event>? gallery) onLongPress;
  final void Function(Event event) onDoubleTap;
  final void Function(Event event) onSwipeReply;
  final void Function(Event event) onResend;
  final void Function(FailedMediaSend failed) onRetryFailedSend;
  final void Function(Event event) onOpenMedia;

  const MessageListView({
    super.key,
    required this.room,
    required this.timeline,
    required this.controller,
    required this.showHiddenMessages,
    required this.canRespond,
    required this.failedSends,
    required this.pendingSend,
    required this.replyTargets,
    required this.onLongPress,
    required this.onDoubleTap,
    required this.onSwipeReply,
    required this.onResend,
    required this.onRetryFailedSend,
    required this.onOpenMedia,
  });

  @override
  State<MessageListView> createState() => _MessageListViewState();
}

const _rowKeyPrefix = 'row-';

class _Arrangement {
  final Timeline timeline;
  final List<Event> messages;
  final Map<String, List<Event>> galleries;
  final Map<String, List<Event>> bursts;
  final List<FailedMediaSend> orphaned;
  final List<FailedMediaSend> singles;
  final Map<String, List<FailedMediaSend>> galleryFailures;
  final bool loadingMore;
  final bool exhausted;
  final bool empty;
  final bool direct;
  final String? lastOwnId;
  final Map<String, Event> index;
  final Set<String> messageIds;
  final Map<String, int> positions;

  _Arrangement._({
    required this.timeline,
    required this.messages,
    required this.galleries,
    required this.bursts,
    required this.orphaned,
    required this.singles,
    required this.galleryFailures,
    required this.loadingMore,
    required this.exhausted,
    required this.empty,
    required this.direct,
    required this.lastOwnId,
    required this.index,
    required this.messageIds,
    required this.positions,
  });

  factory _Arrangement.of(
    Room room,
    Timeline timeline, {
    required bool showHiddenMessages,
    required List<FailedMediaSend> failedSends,
  }) {
    final ownUserId = room.client.userID;
    final direct = room.isDirectChat;
    final visible = timeline.events
        .where(
          (e) => isDisplayableTimelineEvent(
            e,
            showHiddenMessages: showHiddenMessages,
            direct: direct,
          ),
        )
        .toList();
    final grouping = groupGalleries(
      visible,
      ownUserId: ownUserId,
      ownFailedGalleryIds: {
        for (final failed in failedSends)
          if (failed.gallery != null) failed.gallery!.id,
      },
    );
    final updates = groupRoomUpdates(grouping.messages, direct: direct);
    final messages = updates.messages;
    final visibleGalleryIds = {
      for (final e in visible) ?ownGalleryId(e, ownUserId),
    };
    final orphaned = [
      for (final failed in failedSends)
        if (failed.gallery case final gallery?)
          if (!visibleGalleryIds.contains(gallery.id)) failed,
    ];
    final singles = [
      for (final failed in failedSends.reversed)
        if (failed.gallery == null) failed,
    ];
    final galleryFailures = <String, List<FailedMediaSend>>{};
    for (final failed in failedSends) {
      final id = failed.gallery?.id;
      if (id != null) galleryFailures.putIfAbsent(id, () => []).add(failed);
    }
    final loadingMore = timeline.isRequestingHistory;
    return _Arrangement._(
      timeline: timeline,
      messages: messages,
      galleries: grouping.galleries,
      bursts: updates.bursts,
      orphaned: orphaned,
      singles: singles,
      galleryFailures: galleryFailures,
      loadingMore: loadingMore,
      exhausted: !loadingMore && !timeline.canRequestHistory,
      empty:
          !messages.any(isTimelineMessage) &&
          orphaned.isEmpty &&
          singles.isEmpty,
      direct: direct,
      lastOwnId: messages
          .where((e) => e.senderId == ownUserId && isTimelineMessage(e))
          .firstOrNull
          ?.eventId,
      index: {for (final e in timeline.events) e.eventId: e},
      messageIds: {for (final e in messages) e.eventId},
      positions: {
        for (var i = 0; i < messages.length; i++) messages[i].eventId: i,
      },
    );
  }

  bool get hasEndRow => loadingMore || exhausted;

  int get leading => 1 + singles.length + (orphaned.isEmpty ? 0 : 1);

  List<FailedMediaSend> failuresFor(List<Event>? gallery, String? ownUserId) {
    if (gallery == null || gallery.isEmpty) return const [];
    final id = ownGalleryId(gallery.first, ownUserId);
    return id == null ? const [] : galleryFailures[id] ?? const [];
  }
}

class _MessageListViewState extends State<MessageListView> {
  final _memo = RowMemo<MessageRowData>(capacity: 160);
  final _records = <String, MessageRowData>{};
  Timeline? _timeline;
  int _revision = 0;
  _Arrangement? _arrangement;
  int? _arrangedRevision;
  bool? _arrangedShowingHidden;
  List<FailedMediaSend> _arrangedFailures = const [];
  Object? _recordsFor;

  @override
  void initState() {
    super.initState();
    _timeline = widget.timeline.value;
    widget.timeline.addListener(_onTimeline);
  }

  @override
  void didUpdateWidget(MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.timeline, widget.timeline)) {
      oldWidget.timeline.removeListener(_onTimeline);
      widget.timeline.addListener(_onTimeline);
      _onTimeline();
    }
  }

  @override
  void dispose() {
    widget.timeline.removeListener(_onTimeline);
    super.dispose();
  }

  void _onTimeline() {
    final timeline = widget.timeline.value;
    if (!identical(timeline, _timeline)) {
      _timeline = timeline;
      _memo.clear();
    }
    setState(() => _revision++);
  }

  void _roomChanged() => _records.clear();

  void _receiptsChanged() => _records.remove(_arrangement?.lastOwnId);

  _Arrangement _arrange(Timeline timeline) {
    final current = _arrangement;
    if (current != null &&
        identical(current.timeline, timeline) &&
        _arrangedRevision == _revision &&
        _arrangedShowingHidden == widget.showHiddenMessages &&
        listEquals(_arrangedFailures, widget.failedSends)) {
      return current;
    }
    _arrangedRevision = _revision;
    _arrangedShowingHidden = widget.showHiddenMessages;
    _arrangedFailures = List.of(widget.failedSends);
    _records.clear();
    return _arrangement = _Arrangement.of(
      widget.room,
      timeline,
      showHiddenMessages: widget.showHiddenMessages,
      failedSends: widget.failedSends,
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    if (timeline == null) return const SizedBox.shrink();
    return RoomChangesBuilder(
      changes: RoomChanges.state(widget.room),
      onChange: _roomChanged,
      builder: (context) => RoomChangesBuilder(
        changes: RoomChanges.ephemeral(widget.room, 'm.receipt'),
        onChange: _receiptsChanged,
        builder: (context) => _list(context, _arrange(timeline)),
      ),
    );
  }

  Widget _list(BuildContext context, _Arrangement arranged) {
    final messages = arranged.messages;
    final ownUserId = widget.room.client.userID;
    final now = clock.now();
    final labels = DateLabels.of(context);
    final recordsKey = (
      arranged,
      labels,
      widget.canRespond,
      DateUtils.dateOnly(now),
    );
    if (_recordsFor != recordsKey) {
      _recordsFor = recordsKey;
      _records.clear();
    }
    final leading = arranged.leading;
    final singles = arranged.singles;
    final orphaned = arranged.orphaned;

    MessageRowData recordAt(int i, List<FailedMediaSend> failures) =>
        _records[messages[i].eventId] ??= messageRowDataFor(
          event: messages[i],
          timeline: arranged.timeline,
          index: arranged.index,
          older: i + 1 < messages.length ? messages[i + 1] : null,
          newer: i > 0 ? messages[i - 1] : null,
          isLastOwn: messages[i].eventId == arranged.lastOwnId,
          isDirect: arranged.direct,
          gallery: arranged.galleries[messages[i].eventId],
          galleryFailureIndexes: [for (final failed in failures) failed.index],
          canRespond: widget.canRespond,
          now: now,
          labels: labels,
        );

    return ListView.builder(
      controller: widget.controller,
      reverse: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: leading + messages.length + (arranged.hasEndRow ? 1 : 0),
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        if (!key.value.startsWith(_rowKeyPrefix)) return null;
        final i = arranged.positions[key.value.substring(_rowKeyPrefix.length)];
        return i == null ? null : i + leading;
      },
      itemBuilder: (context, position) {
        if (position == 0) {
          return ValueListenableBuilder<PendingAttachmentSend?>(
            valueListenable: widget.pendingSend,
            builder: (context, pending, _) {
              final show = pendingSendNeedsSyntheticTile(
                pendingEventId: pending?.eventId,
                timelineEventIds: arranged.messageIds,
              );
              return show
                  ? PendingAttachmentTile(pendingSend: pending!)
                  : const SizedBox.shrink();
            },
          );
        }
        if (position <= singles.length) {
          return FailedMediaTile(
            failed: [singles[position - 1]],
            onRetry: widget.onRetryFailedSend,
          );
        }
        if (orphaned.isNotEmpty && position == singles.length + 1) {
          return FailedMediaTile(
            failed: orphaned,
            onRetry: widget.onRetryFailedSend,
          );
        }
        final i = position - leading;
        if (i >= messages.length) {
          return _EndRow(
            room: widget.room,
            exhausted: arranged.exhausted,
            empty: arranged.empty,
            pendingSend: widget.pendingSend,
          );
        }

        final message = messages[i];
        final older = i + 1 < messages.length ? messages[i + 1] : null;
        final burst = arranged.bursts[message.eventId];
        if (burst != null) {
          final dayLabel = dayLabelFor(
            message,
            older,
            labels: labels,
            now: now,
          );
          return Column(
            key: ValueKey('$_rowKeyPrefix${message.eventId}'),
            children: [
              if (dayLabel != null) DateDivider(label: dayLabel),
              RoomUpdateTile(lines: describeRoomUpdates(context.l10n, burst)),
            ],
          );
        }
        final gallery = arranged.galleries[message.eventId];
        final failures = arranged.failuresFor(gallery, ownUserId);
        final record = recordAt(i, failures);
        return _memo.obtain(message.eventId, record, () {
          final tile = MessageTile(
            key: ValueKey(message.eventId),
            data: record,
            event: message,
            timeline: arranged.timeline,
            replyTarget: arranged.index[record.replyToId],
            replyTargets: widget.replyTargets,
            pendingSend: widget.pendingSend,
            gallery: gallery,
            galleryFailures: failures,
            onLongPress: () => widget.onLongPress(message, gallery),
            onDoubleTap: record.canRespond
                ? () => widget.onDoubleTap(message)
                : null,
            onSwipeReply: record.canRespond
                ? () => widget.onSwipeReply(message)
                : null,
            onResend: (event) => widget.onResend(event),
            onRetryFailedSend: (failed) => widget.onRetryFailedSend(failed),
            onOpenMedia: (event) => widget.onOpenMedia(event),
          );
          final dayLabel = record.dayLabel;
          return Column(
            key: ValueKey('$_rowKeyPrefix${message.eventId}'),
            children: [
              if (dayLabel != null) DateDivider(label: dayLabel),
              tile,
            ],
          );
        });
      },
    );
  }
}

class _EndRow extends StatelessWidget {
  final Room room;
  final bool exhausted;
  final bool empty;
  final ValueListenable<PendingAttachmentSend?> pendingSend;

  const _EndRow({
    required this.room,
    required this.exhausted,
    required this.empty,
    required this.pendingSend,
  });

  @override
  Widget build(BuildContext context) {
    if (!exhausted) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: InlineSpinner(size: 24)),
      );
    }
    if (empty) {
      return ValueListenableBuilder<PendingAttachmentSend?>(
        valueListenable: pendingSend,
        builder: (context, pending, _) => pending == null
            ? EmptyRoomNotice(room: room)
            : const SizedBox.shrink(),
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Center(
        child: Text(
          context.l10n.chatNoEarlierMessages,
          style: theme.textTheme.labelMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
