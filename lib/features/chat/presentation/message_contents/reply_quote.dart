import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/matrix/quoted_message_box.dart';
import '../../../../core/ui/zuno_theme.dart';
import '../../data/message_kinds.dart';
import '../message_bubble.dart';
import '../reply_target_cache.dart';
import 'media_message.dart';

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
    _resolve();
  }

  @override
  void didUpdateWidget(ReplyQuote oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
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
            ? 'Original message not available'
            : 'Loading…',
        fill: fill,
        muted: muted,
      );
    }

    final displayEvent = original.getDisplayEvent(widget.timeline);
    final kind = classifyAttachment(displayEvent);
    return QuotedMessageBox(
      senderName: original.senderFromMemoryOrFallback.calcDisplayname(),
      snippet: previewSnippet(original, widget.timeline),
      icon: switch (kind) {
        AttachmentKind.image => Icons.photo_outlined,
        AttachmentKind.video => Icons.videocam_outlined,
        AttachmentKind.location => Icons.location_on_outlined,
        _ => null,
      },
      thumbnail: switch (kind) {
        AttachmentKind.image || AttachmentKind.video => attachmentThumbnail(
          displayEvent,
          placeholder: ColoredBox(color: theme.colorScheme.surfaceContainer),
        ),
        _ => null,
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
