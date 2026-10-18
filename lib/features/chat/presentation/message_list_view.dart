import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/room_updates.dart';
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
  final Timeline timeline;
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
  });

  @override
  State<MessageListView> createState() => _MessageListViewState();
}

const _rowKeyPrefix = 'row-';

class _MessageListViewState extends State<MessageListView> {
  final _memo = RowMemo<MessageRowData>(capacity: 160);

  @override
  void didUpdateWidget(MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.timeline, widget.timeline)) _memo.clear();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    final visible = timeline.events
        .where(
          (e) => isDisplayableTimelineEvent(
            e,
            showHiddenMessages: widget.showHiddenMessages,
          ),
        )
        .toList();
    final ownUserId = widget.room.client.userID;
    final grouping = groupGalleries(
      visible,
      ownUserId: ownUserId,
      ownFailedGalleryIds: {
        for (final failed in widget.failedSends)
          if (failed.gallery != null) failed.gallery!.id,
      },
    );
    final updates = groupRoomUpdates(grouping.messages);
    final messages = updates.messages;
    final orphaned = widget.failedSends.where((failed) {
      final id = failed.gallery?.id;
      if (id == null) return false;
      return !visible.any((e) => ownGalleryId(e, ownUserId) == id);
    }).toList();
    final singles = [
      for (final failed in widget.failedSends.reversed)
        if (failed.gallery == null) failed,
    ];
    final loadingMore = timeline.isRequestingHistory;
    final exhausted = !loadingMore && !timeline.canRequestHistory;
    final lastOwnId = messages
        .where((e) => e.senderId == ownUserId && isTimelineMessage(e))
        .firstOrNull
        ?.eventId;
    final index = {for (final e in timeline.events) e.eventId: e};
    final messageIds = {for (final e in messages) e.eventId};
    final positions = {
      for (var i = 0; i < messages.length; i++) messages[i].eventId: i,
    };
    final now = DateTime.now();
    final labels = DateLabels.of(context);
    final hasEndRow = loadingMore || exhausted;
    final leading = 1 + singles.length + (orphaned.isEmpty ? 0 : 1);

    List<FailedMediaSend> failuresFor(List<Event>? gallery) {
      if (gallery == null || gallery.isEmpty) return const [];
      final id = ownGalleryId(gallery.first, ownUserId);
      if (id == null) return const [];
      return [
        for (final failed in widget.failedSends)
          if (failed.gallery?.id == id) failed,
      ];
    }

    return ListView.builder(
      controller: widget.controller,
      reverse: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: leading + messages.length + (hasEndRow ? 1 : 0),
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        if (!key.value.startsWith(_rowKeyPrefix)) return null;
        final i = positions[key.value.substring(_rowKeyPrefix.length)];
        return i == null ? null : i + leading;
      },
      itemBuilder: (context, position) {
        if (position == 0) {
          return ValueListenableBuilder<PendingAttachmentSend?>(
            valueListenable: widget.pendingSend,
            builder: (context, pending, _) {
              final show = pendingSendNeedsSyntheticTile(
                pendingEventId: pending?.eventId,
                timelineEventIds: messageIds,
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
            exhausted: exhausted,
            empty:
                !messages.any(isTimelineMessage) &&
                orphaned.isEmpty &&
                singles.isEmpty,
            pendingSend: widget.pendingSend,
          );
        }

        final message = messages[i];
        final older = i + 1 < messages.length ? messages[i + 1] : null;
        final burst = updates.bursts[message.eventId];
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
        final gallery = grouping.galleries[message.eventId];
        final failures = failuresFor(gallery);
        final record = messageRowDataFor(
          event: message,
          timeline: timeline,
          index: index,
          older: older,
          newer: i > 0 ? messages[i - 1] : null,
          isLastOwn: message.eventId == lastOwnId,
          gallery: gallery,
          galleryFailureIndexes: [for (final failed in failures) failed.index],
          canRespond: widget.canRespond,
          now: now,
          labels: labels,
        );
        return _memo.obtain(message.eventId, record, () {
          final tile = MessageTile(
            key: ValueKey(message.eventId),
            data: record,
            event: message,
            timeline: timeline,
            replyTarget: index[record.replyToId],
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
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
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
