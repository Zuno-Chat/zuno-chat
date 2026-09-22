import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../core/location/location_message.dart';
import '../../../core/matrix/image_caption.dart';
import '../../../core/matrix/link_preview_card.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/state_event_description.dart';
import '../../../core/matrix/undecryptable_event.dart';
import '../../../core/matrix/urls.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../location/presentation/location_bubble.dart';
import '../../location/presentation/location_map_page.dart';
import '../data/message_kinds.dart';
import '../data/message_row_data.dart';
import '../data/pending_attachment_send.dart';
import 'message_bubble.dart';
import 'message_contents/call_summary_tile.dart';
import 'message_contents/file_message.dart';
import 'message_contents/media_message.dart';
import 'message_contents/reactions_row.dart';
import 'message_contents/reply_quote.dart';
import 'message_contents/text_message.dart';
import 'message_contents/voice_message.dart';
import 'message_meta.dart';
import 'not_sent.dart';
import 'reply_target_cache.dart';
import 'swipe_to_reply.dart';
import 'undecryptable_message.dart';

class MessageTile extends StatelessWidget {
  final MessageRowData data;
  final Event event;
  final Timeline timeline;
  final Event? replyTarget;
  final ReplyTargetCache replyTargets;
  final ValueListenable<PendingAttachmentSend?> pendingSend;
  final List<Event>? gallery;
  final List<FailedMediaSend> galleryFailures;
  final VoidCallback onLongPress;
  final VoidCallback? onSwipeReply;
  final void Function(Event) onResend;
  final void Function(FailedMediaSend) onRetryFailedSend;

  const MessageTile({
    super.key,
    required this.data,
    required this.event,
    required this.timeline,
    required this.replyTarget,
    required this.replyTargets,
    required this.pendingSend,
    required this.gallery,
    required this.galleryFailures,
    required this.onLongPress,
    required this.onSwipeReply,
    required this.onResend,
    required this.onRetryFailedSend,
  });

  @override
  Widget build(BuildContext context) {
    final displayEvent = event.getDisplayEvent(timeline);
    final isHiddenState = displayEvent.stateKey != null;
    if (isHiddenState || isCallSignalingMessage(displayEvent.messageType)) {
      return _HiddenEventRow(
        text: isHiddenState
            ? (describeStateEvent(displayEvent) ?? '${displayEvent.type} event')
            : 'Hidden message: ${displayEvent.body}',
      );
    }

    final own = data.isOwn;
    final isUndecryptable = isUndecryptableEvent(displayEvent);
    final unreadable = data.redacted || isUndecryptable;
    final kind = classifyAttachment(displayEvent);
    final gallery = this.gallery;
    final isGallery = gallery != null;
    final isImage = !isGallery && kind == AttachmentKind.image;
    final isVideo = !isGallery && kind == AttachmentKind.video;
    final isMedia = !unreadable && (isGallery || isImage || isVideo);
    final isLocation = !unreadable && kind == AttachmentKind.location;
    final isFile = !unreadable && kind == AttachmentKind.file;
    final isVoice = !unreadable && kind == AttachmentKind.voice;
    final tightWidth = isMedia || isLocation || isFile || isVoice;
    final callSummary = unreadable ? null : CallSummary.fromEvent(displayEvent);
    final notSent = isNotSent(event);
    final caption = isMedia && !isGallery ? imageCaption(displayEvent) : null;
    final body = displayBody(event, timeline);

    final meta = MessageMeta(
      time: data.timeLabel,
      own: own,
      edited: data.edited,
      status: data.metaStatus,
    );
    final mediaMeta = MessageMeta(
      time: data.timeLabel,
      own: own,
      status: data.metaStatus,
      onMedia: true,
    );

    Widget sending(Widget Function(PendingAttachmentSend? pending) build) {
      if (!event.status.isSending) return build(null);
      return ValueListenableBuilder<PendingAttachmentSend?>(
        valueListenable: pendingSend,
        builder: (context, pending, _) => build(pending),
      );
    }

    final Widget content;
    if (data.redacted) {
      content = _NoticeContent(
        icon: Icons.delete_outline,
        text: 'Message deleted',
        own: own,
        meta: meta,
      );
    } else if (isUndecryptable) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const UndecryptableMessageContent(),
          Padding(padding: const EdgeInsets.only(top: 3), child: meta),
        ],
      );
    } else if (isGallery) {
      content = sending(
        (pending) => GalleryMessage(
          events: gallery,
          failed: galleryFailures,
          onRetry: onRetryFailedSend,
          pendingSend: pending,
          mediaMeta: mediaMeta,
        ),
      );
    } else if (isImage) {
      content = sending(
        (pending) => ImageMessage(
          event: displayEvent,
          pendingSend: pending?.eventId == displayEvent.eventId
              ? pending
              : null,
          mediaMeta: mediaMeta,
          showTimeOverlay: caption == null,
        ),
      );
    } else if (isVideo) {
      content = sending(
        (pending) => VideoMessage(
          event: displayEvent,
          pendingSend: pending?.eventId == displayEvent.eventId
              ? pending
              : null,
          mediaMeta: mediaMeta,
          showTimeOverlay: caption == null,
        ),
      );
    } else if (isVoice) {
      content = VoiceMessage(event: displayEvent, own: own, meta: meta);
    } else if (isFile) {
      content = FileMessage(event: displayEvent, own: own, meta: meta);
    } else if (isLocation) {
      content = LocationBubble(
        geo: locationOf(displayEvent),
        radius: mediaRadius,
        trailing: meta,
        onOpen: (geo) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LocationMapPage(
              geo: geo,
              senderName: data.senderName,
              sentAt: event.originServerTs,
            ),
          ),
        ),
      );
    } else if (callSummary != null) {
      content = CallSummaryTile(summary: callSummary, own: own, meta: meta);
    } else {
      content = TextMessage(
        displayEvent: displayEvent,
        body: body,
        meta: notSent ? null : meta,
      );
    }

    final linkUrl =
        (linkPreviewsFeatureAvailable &&
            data.linkPreviews &&
            kind == AttachmentKind.none &&
            !unreadable)
        ? firstLinkIn(body)
        : null;

    final replyToId = data.replyToId;
    final EdgeInsets bubblePadding;
    if (isMedia || isLocation) {
      bubblePadding = const EdgeInsets.all(mediaInset);
    } else if (tightWidth) {
      bubblePadding = const EdgeInsets.fromLTRB(8, 8, 12, 7);
    } else {
      bubblePadding = const EdgeInsets.fromLTRB(12, 7, 12, 7);
    }
    final bubble = MessageBubble(
      own: own,
      position: data.position,
      senderName: !own && !data.isDirect && data.startsRun
          ? data.senderName
          : null,
      quote: replyToId == null
          ? null
          : ReplyQuote(
              timeline: timeline,
              eventId: replyToId,
              target: replyTarget,
              cache: replyTargets,
              own: own,
            ),
      padding: bubblePadding,
      onTap: notSent ? () => onResend(event) : null,
      onLongPress: unreadable ? null : onLongPress,
      child: Column(
        crossAxisAlignment: notSent
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 3),
              child: TuckedMeta(
                meta: meta,
                textBuilder: (spacer) =>
                    Text.rich(TextSpan(text: caption, children: [spacer])),
              ),
            ),
          if (linkUrl != null)
            LinkPreviewCard(url: linkUrl, client: event.room.client),
          if (notSent)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: NotSentRow(),
            ),
        ],
      ),
    );

    final screenWidth = MediaQuery.sizeOf(context).width;
    final sizedBubble = ConstrainedBox(
      constraints: tightWidth
          ? BoxConstraints.tightFor(width: screenWidth * 2 / 3)
          : BoxConstraints(maxWidth: screenWidth * 3 / 4),
      child: bubble,
    );

    final hasReactions = data.reactions.isNotEmpty;
    final bubbleWithReactions = !hasReactions
        ? sizedBubble
        : Stack(
            clipBehavior: Clip.none,
            children: [
              sizedBubble,
              Positioned(
                bottom: -reactionOverflow,
                left: own ? null : 10,
                right: own ? 10 : null,
                child: ReactionsRow(event: event, timeline: timeline),
              ),
            ],
          );

    final showGutter = !own && !data.isDirect;
    final row = Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: data.startsRun ? 8 : 2,
        bottom: hasReactions ? reactionOverflowGap : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (showGutter) ...[
            SizedBox(
              width: 32,
              height: 32,
              child: data.startsRun
                  ? MxcAvatar(
                      client: event.room.client,
                      avatarUrl: data.senderAvatar,
                      fallbackText: data.senderName,
                      toneSeed: event.senderId,
                      radius: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(child: bubbleWithReactions),
        ],
      ),
    );

    final onSwipeReply = this.onSwipeReply;
    if (unreadable || onSwipeReply == null) return row;
    return SwipeToReply(onReply: onSwipeReply, child: row);
  }
}

class _NoticeContent extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool own;
  final Widget meta;

  const _NoticeContent({
    required this.icon,
    required this.text,
    required this.own,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = bubbleMuted(theme, own: own);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const SizedBox(width: 10),
        meta,
      ],
    );
  }
}

class _HiddenEventRow extends StatelessWidget {
  final String text;

  const _HiddenEventRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.visibility_off_outlined, size: 16, color: muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontStyle: FontStyle.italic,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
