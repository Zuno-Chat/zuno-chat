import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/cover_image.dart';
import '../../../../core/matrix/event_display.dart';
import '../../../../core/matrix/message_icons.dart';
import '../../../../core/matrix/quoted_message_box.dart';
import '../../../../core/ui/zuno_theme.dart';
import '../message_bubble.dart';
import '../reply_target_cache.dart';

class ReplyQuote extends StatefulWidget {
  final Timeline timeline;
  final String eventId;
  final Event? target;
  final ReplyTargetCache cache;
  final bool own;

  const ReplyQuote({
    super.key,
    required this.timeline,
    required this.eventId,
    required this.target,
    required this.cache,
    required this.own,
  });

  @override
  State<ReplyQuote> createState() => _ReplyQuoteState();
}

class _ReplyQuoteState extends State<ReplyQuote> {
  @override
  void initState() {
    super.initState();
    widget.cache.addListener(_onCacheChanged);
    _resolve();
  }

  @override
  void didUpdateWidget(ReplyQuote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache) {
      oldWidget.cache.removeListener(_onCacheChanged);
      widget.cache.addListener(_onCacheChanged);
    }
    _resolve();
  }

  @override
  void dispose() {
    widget.cache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (mounted) setState(() {});
  }

  void _resolve() {
    if (widget.target != null || widget.cache.isResolved(widget.eventId)) {
      return;
    }
    final eventId = widget.eventId;
    widget.cache.fetch(eventId).then((_) {
      if (mounted && widget.eventId == eventId) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = quoteFill(
      surface: theme.colorScheme.surface,
      bubble: bubbleFill(theme, own: widget.own),
    );
    final muted = bubbleMuted(theme, own: widget.own);
    final original = widget.target ?? widget.cache.resolved(widget.eventId);
    if (original == null) {
      return _QuotedMessageNotice(
        text: widget.cache.isResolved(widget.eventId)
            ? context.l10n.chatOriginalUnavailable
            : context.l10n.commonLoading,
        fill: fill,
        muted: muted,
      );
    }

    final displayEvent = original.getDisplayEvent(widget.timeline);
    final summary = summarize(context.l10n, displayEvent);
    return QuotedMessageBox(
      senderName: original.senderFromMemoryOrFallback.calcDisplayname(),
      snippet: summary.text,
      icon: messageIcon(summary),
      thumbnail: switch (summary.kind) {
        MessageKind.photo || MessageKind.video => attachmentThumbnail(
          displayEvent,
          placeholder: ColoredBox(color: theme.colorScheme.surfaceContainer),
          shownAt: quotedThumbnailSize,
        ),
        MessageKind.text ||
        MessageKind.voice ||
        MessageKind.file ||
        MessageKind.location ||
        MessageKind.liveLocation ||
        MessageKind.callSummary ||
        MessageKind.deleted ||
        MessageKind.undecryptable ||
        MessageKind.nonMessage ||
        MessageKind.hiddenSignaling => null,
      },
      borderRadius: ZunoRadius.small,
      fill: fill,
      muted: muted,
    );
  }
}

class _QuotedMessageNotice extends StatelessWidget {
  final String text;
  final Color fill;
  final Color muted;

  const _QuotedMessageNotice({
    required this.text,
    required this.fill,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(ZunoRadius.small),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: muted, fontStyle: FontStyle.italic),
      ),
    );
  }
}
