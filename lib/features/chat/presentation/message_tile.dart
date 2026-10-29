import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/matrixrtc/call_summary_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_viewing.dart';
import '../../../core/location/location_message.dart';
import '../../../core/matrix/event_display.dart';
import '../../../core/matrix/forwarded_message.dart';
import '../../../core/matrix/image_caption.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/security/security_emphasis.dart';
import '../../location/presentation/live_location_map_page.dart';
import '../../location/presentation/live_location_tile.dart';
import '../../location/presentation/location_bubble.dart';
import '../../location/presentation/location_map_page.dart';
import '../data/message_kinds.dart';
import '../data/message_row_data.dart';
import '../data/pending_attachment_send.dart';
import '../data/unsent_events.dart';
import 'message_bubble.dart';
import 'message_contents/call_summary_tile.dart';
import 'message_contents/file_message.dart';
import 'message_contents/forwarded_label.dart';
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
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSwipeReply;
  final void Function(Event) onResend;
  final void Function(FailedMediaSend) onRetryFailedSend;
  final void Function(Event event) onOpenMedia;

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
    required this.onDoubleTap,
    required this.onSwipeReply,
    required this.onResend,
    required this.onRetryFailedSend,
    required this.onOpenMedia,
  });

  @override
  Widget build(BuildContext context) {
    final displayEvent = event.getDisplayEvent(timeline);
    final kind = messageKindOf(displayEvent);
    if (kind != MessageKind.liveLocation) {
      return _tile(context, displayEvent, kind, liveShare: null);
    }
    return Consumer(
      builder: (context, ref, _) => _tile(
        context,
        displayEvent,
        kind,
        liveShare: ref.watch(
          liveSharesProvider(event.room.id)
              .select((shares) => liveShareStartedBy(shares, displayEvent)),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    Event displayEvent,
    MessageKind kind, {
    required LiveShareView? liveShare,
  }) {
    final l10n = context.l10n;
    final gallery = this.gallery;
    final look = _lookOf(
      kind,
      gallery: gallery != null,
      liveMap: liveShare != null,
    );
    if (look == null) {
      final text = summarize(l10n, displayEvent).text;
      return _HiddenEventRow(
        text: kind == MessageKind.hiddenSignaling
            ? l10n.chatHiddenMessage(text)
            : text,
      );
    }

    final own = data.isOwn;
    final unsent = notSentBehind(event, timeline);
    final notSent = unsent != null;
    final shown = withEditApplied(event, displayEvent);
    final caption = look == _Look.photo || look == _Look.video
        ? imageCaption(shown)
        : null;

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

    PendingAttachmentSend? pendingHere(PendingAttachmentSend? pending) =>
        pending?.eventId == shown.eventId ? pending : null;

    final content = switch (look) {
      _Look.deleted => _NoticeContent(
        icon: Icons.delete_outline,
        text: l10n.chatMessageDeleted,
        own: own,
        meta: meta,
      ),
      _Look.undecryptable => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const UndecryptableMessageContent(),
          Padding(padding: const EdgeInsets.only(top: 3), child: meta),
        ],
      ),
      _Look.gallery => sending(
        (pending) => GalleryMessage(
          events: gallery!,
          failed: galleryFailures,
          onRetry: onRetryFailedSend,
          pendingSend: pending,
          mediaMeta: mediaMeta,
          onOpen: onOpenMedia,
        ),
      ),
      _Look.photo => sending(
        (pending) => ImageMessage(
          event: shown,
          pendingSend: pendingHere(pending),
          mediaMeta: mediaMeta,
          showTimeOverlay: caption == null,
          onOpen: onOpenMedia,
        ),
      ),
      _Look.video => sending(
        (pending) => VideoMessage(
          event: shown,
          pendingSend: pendingHere(pending),
          mediaMeta: mediaMeta,
          showTimeOverlay: caption == null,
          onOpen: onOpenMedia,
        ),
      ),
      _Look.voice => VoiceMessage(event: shown, own: own, meta: meta),
      _Look.file => FileMessage(event: shown, own: own, meta: meta),
      _Look.location => LocationBubble(
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
      ),
      _Look.liveMap => LiveLocationTile(
        room: event.room,
        share: liveShare!,
        radius: mediaRadius,
        muted: bubbleMuted(Theme.of(context), own: own),
        trailing: meta,
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                LiveLocationMapPage(room: event.room, focus: event.senderId),
          ),
        ),
      ),
      _Look.liveEnded => _NoticeContent(
        icon: Icons.share_location_outlined,
        text: l10n.chatLiveLocationEnded,
        own: own,
        meta: meta,
      ),
      _Look.callSummary => CallSummaryTile(
        summary: CallSummary.fromEvent(displayEvent)!,
        own: own,
        meta: meta,
      ),
      _Look.text => TextMessage(
        displayEvent: displayEvent,
        body: displayBody(event, timeline),
        meta: notSent ? null : meta,
      ),
    };

    final replyToId = data.replyToId;
    final unreadable = look.unreadable;
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
      padding: look.framed
          ? const EdgeInsets.all(mediaInset)
          : look.tight
          ? const EdgeInsets.fromLTRB(8, 8, 12, 7)
          : const EdgeInsets.fromLTRB(12, 7, 12, 7),
      onTap: unsent == null ? null : () => onResend(unsent),
      onLongPress: unreadable ? null : onLongPress,
      onDoubleTap: unreadable ? null : onDoubleTap,
      child: Column(
        crossAxisAlignment: notSent
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isForwarded(shown))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: look.framed
                    ? const EdgeInsets.fromLTRB(6, 3, 8, 5)
                    : const EdgeInsets.only(bottom: 4),
                child: ForwardedLabel(own: own),
              ),
            ),
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
      constraints: look.tight
          ? BoxConstraints.tightFor(width: screenWidth * 2 / 3)
          : BoxConstraints(maxWidth: screenWidth * 3 / 4),
      child: bubble,
    );

    final hasReactions = data.reactions.isNotEmpty;
    final sentInClear = data.sentInClear;
    final decoratedBubble = !hasReactions && !sentInClear
        ? sizedBubble
        : Stack(
            clipBehavior: Clip.none,
            children: [
              sizedBubble,
              if (hasReactions)
                Positioned(
                  bottom: -reactionOverflow,
                  left: own ? null : 10,
                  right: own ? 10 : null,
                  child: ReactionsRow(event: event, timeline: timeline),
                ),
              if (sentInClear)
                Positioned(
                  top: 0,
                  left: own ? -_badgeSize / 2 : null,
                  right: own ? null : -_badgeSize / 2,
                  child: const _NotEncryptedBadge(),
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
          Flexible(child: decoratedBubble),
        ],
      ),
    );

    final onSwipeReply = this.onSwipeReply;
    if (unreadable || onSwipeReply == null) return row;
    return SwipeToReply(onReply: onSwipeReply, child: row);
  }
}

enum _Look {
  deleted,
  undecryptable,
  text,
  callSummary,
  liveEnded,
  voice(tight: true),
  file(tight: true),
  gallery(framed: true),
  photo(framed: true),
  video(framed: true),
  location(framed: true),
  liveMap(framed: true);

  const _Look({this.framed = false, bool tight = false})
    : tight = framed || tight;

  final bool framed;
  final bool tight;

  bool get unreadable => this == deleted || this == undecryptable;
}

_Look? _lookOf(
  MessageKind kind, {
  required bool gallery,
  required bool liveMap,
}) => switch (kind) {
  MessageKind.nonMessage || MessageKind.hiddenSignaling => null,
  MessageKind.deleted => _Look.deleted,
  MessageKind.undecryptable => _Look.undecryptable,
  _ when gallery => _Look.gallery,
  MessageKind.photo => _Look.photo,
  MessageKind.video => _Look.video,
  MessageKind.voice => _Look.voice,
  MessageKind.file => _Look.file,
  MessageKind.location => _Look.location,
  MessageKind.liveLocation => liveMap ? _Look.liveMap : _Look.liveEnded,
  MessageKind.callSummary => _Look.callSummary,
  MessageKind.text => _Look.text,
};

const _badgeSize = 20.0;

class _NotEncryptedBadge extends StatelessWidget {
  const _NotEncryptedBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: _badgeSize,
      height: _badgeSize,
      decoration: BoxDecoration(
        color: notEncryptedColor(context),
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 1.5),
      ),
      child: Icon(
        notEncryptedIcon,
        size: 12,
        color: colors.onError,
        semanticLabel: context.l10n.chatMessageNotEncrypted,
      ),
    );
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
