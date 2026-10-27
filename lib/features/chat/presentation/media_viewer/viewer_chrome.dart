import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../../core/format/date_labels.dart';
import '../../../../core/format/human_units.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/image_caption.dart';
import '../../../../core/matrix/media_gallery_group.dart';
import '../../../../core/matrix/mxc_avatar.dart';
import '../../../../core/matrix/reactions.dart';
import '../../../../core/ui/frosted_surface.dart';
import '../../../../core/ui/zuno_colors.dart';
import '../../../../core/ui/zuno_motion.dart';
import '../forward_icon.dart';
import 'video_playback.dart';

const _maxGalleryDots = 10;

const _overMedia = [Shadow(color: mediaScrimColor, blurRadius: 6)];

class ViewerChrome extends StatelessWidget {
  final Event event;
  final bool visible;
  final VideoPlayback? playback;
  final bool muted;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onToggleMute;
  final VoidCallback onInteraction;
  final VoidCallback? onMore;
  final VoidCallback? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final List<ReactionSummary> reactions;
  final ValueChanged<String>? onToggleReaction;

  const ViewerChrome({
    required this.event,
    required this.visible,
    required this.playback,
    required this.muted,
    required this.onBack,
    required this.onShare,
    required this.onSave,
    required this.onToggleMute,
    required this.onInteraction,
    this.onMore,
    this.onReact,
    this.onReply,
    this.onForward,
    this.reactions = const [],
    this.onToggleReaction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final caption = imageCaption(event);
    final gallery = galleryGroupOf(event);
    final playback = this.playback;
    return IgnorePointer(
      ignoring: !visible,
      child: Listener(
        onPointerDown: (_) => onInteraction(),
        behavior: HitTestBehavior.translucent,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: ZunoDurations.fast,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _TopBar(
                      event: event,
                      onBack: onBack,
                      onMore: onMore,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 12,
                      children: [
                        if (caption != null) _Caption(text: caption),
                        if (gallery != null) _GalleryPosition(gallery: gallery),
                        if (playback != null)
                          _VideoTimeline(
                            playback: playback,
                            muted: muted,
                            onToggleMute: onToggleMute,
                          ),
                        if (reactions.isNotEmpty)
                          _ReactionChips(
                            reactions: reactions,
                            onToggle: onToggleReaction,
                          ),
                        _ActionPill(
                          myReaction: reactions
                              .where((reaction) => reaction.reactedByMe)
                              .firstOrNull
                              ?.key,
                          onReact: onReact,
                          onReply: onReply,
                          onForward: onForward,
                          onShare: onShare,
                          onSave: onSave,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Event event;
  final VoidCallback onBack;
  final VoidCallback? onMore;

  const _TopBar({required this.event, required this.onBack, this.onMore});

  @override
  Widget build(BuildContext context) {
    final onMore = this.onMore;
    return Row(
      spacing: 8,
      children: [
        _RoundButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
        ),
        Expanded(
          child: Center(child: _SenderPill(event: event)),
        ),
        if (onMore != null)
          _RoundButton(
            icon: const Icon(Icons.more_vert),
            tooltip: context.l10n.commonMore,
            onPressed: onMore,
          )
        else
          const SizedBox.square(dimension: _RoundButton.size),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  static const size = 44.0;

  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => FrostedSurface(
    circle: true,
    child: SizedBox.square(
      dimension: size,
      child: IconButton(icon: icon, tooltip: tooltip, onPressed: onPressed),
    ),
  );
}

class _SenderPill extends StatelessWidget {
  final Event event;

  const _SenderPill({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sender = event.senderFromMemoryOrFallback;
    final name = sender.calcDisplayname();
    final labels = DateLabels.of(context);
    final sentAt = event.originServerTs;
    final sent = labels.dayAndTime(sentAt, now: clock.now());
    return FrostedSurface(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(5, 5, 16, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            MxcAvatar(
              client: event.room.client,
              avatarUrl: sender.avatarUrl,
              fallbackText: name,
              toneSeed: event.senderId,
              radius: 16,
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    sent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatefulWidget {
  final String text;

  const _Caption({required this.text});

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: onMediaColor, shadows: _overMedia);
    final text = Text(
      widget.text,
      textAlign: TextAlign.center,
      maxLines: _expanded ? null : 3,
      overflow: _expanded ? null : TextOverflow.ellipsis,
      style: style,
    );
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedSize(
        duration: ZunoDurations.fast,
        alignment: Alignment.bottomCenter,
        child: _expanded
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: SingleChildScrollView(child: text),
              )
            : text,
      ),
    );
  }
}

class _GalleryPosition extends StatelessWidget {
  final GalleryGroupRef gallery;

  const _GalleryPosition({required this.gallery});

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.matrixGalleryPosition(
      gallery.index + 1,
      gallery.count,
    );
    if (gallery.count > _maxGalleryDots) {
      return Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: onMediaColor, shadows: _overMedia),
      );
    }
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          for (var i = 0; i < gallery.count; i++)
            AnimatedContainer(
              duration: ZunoDurations.fast,
              width: i == gallery.index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == gallery.index ? onMediaColor : onMediaFaintColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoTimeline extends StatefulWidget {
  final VideoPlayback playback;
  final bool muted;
  final VoidCallback onToggleMute;

  const _VideoTimeline({
    required this.playback,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  State<_VideoTimeline> createState() => _VideoTimelineState();
}

class _VideoTimelineState extends State<_VideoTimeline> {
  double? _draggedMs;

  Widget _row(BuildContext context, Duration position, Duration total) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: onMediaColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final ready = total > Duration.zero;
    final dragged = _draggedMs;
    final at = dragged != null
        ? Duration(milliseconds: dragged.round())
        : (position > total ? total : position);
    return Row(
      children: [
        Text(formatDuration(at), style: style),
        Expanded(
          child: Slider(
            value: ready ? at.inMilliseconds.toDouble() : 0,
            max: ready ? total.inMilliseconds.toDouble() : 1,
            onChanged: ready ? (ms) => setState(() => _draggedMs = ms) : null,
            onChangeEnd: ready
                ? (ms) {
                    setState(() => _draggedMs = null);
                    widget.playback.seekTo(Duration(milliseconds: ms.round()));
                  }
                : null,
          ),
        ),
        Text(formatDuration(total), style: style),
        IconButton(
          icon: Icon(
            widget.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          ),
          tooltip: widget.muted
              ? context.l10n.chatMediaUnmute
              : context.l10n.chatMediaMute,
          onPressed: widget.onToggleMute,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    return FrostedSurface(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
        child: ListenableBuilder(
          listenable: playback,
          builder: (context, _) {
            final controller = playback.controller;
            if (controller == null) {
              return _row(context, Duration.zero, Duration.zero);
            }
            return ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) =>
                  _row(context, value.position, value.duration),
            );
          },
        ),
      ),
    );
  }
}

class _ReactionChips extends StatelessWidget {
  final List<ReactionSummary> reactions;
  final ValueChanged<String>? onToggle;

  const _ReactionChips({required this.reactions, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final count = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: onMediaColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final onToggle = this.onToggle;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final reaction in reactions)
          Semantics(
            button: onToggle != null,
            selected: reaction.reactedByMe,
            child: FrostedSurface(
              highlighted: reaction.reactedByMe,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onToggle == null ? null : () => onToggle(reaction.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Text(
                          reaction.key,
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text('${reaction.count}', style: count),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String? myReaction;
  final VoidCallback? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const _ActionPill({
    required this.myReaction,
    required this.onReact,
    required this.onReply,
    required this.onForward,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onReact = this.onReact;
    final onReply = this.onReply;
    final onForward = this.onForward;
    Widget action(Widget icon, String tooltip, VoidCallback onPressed) =>
        SizedBox(
          width: 52,
          height: 46,
          child: IconButton(icon: icon, tooltip: tooltip, onPressed: onPressed),
        );
    final myReaction = this.myReaction;
    return FrostedSurface(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (onReact != null)
              action(
                myReaction == null
                    ? const Icon(Icons.add_reaction_outlined)
                    : Text(myReaction, style: const TextStyle(fontSize: 20)),
                l10n.chatReact,
                onReact,
              ),
            if (onReply != null)
              action(
                const Icon(Icons.reply_outlined),
                l10n.commonReply,
                onReply,
              ),
            if (onForward != null)
              action(const ForwardIcon(), l10n.chatForward, onForward),
            action(const Icon(Icons.share_outlined), l10n.commonShare, onShare),
            action(
              const Icon(Icons.download_outlined),
              l10n.commonSave,
              onSave,
            ),
          ],
        ),
      ),
    );
  }
}
