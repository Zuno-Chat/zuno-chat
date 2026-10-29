import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/format/human_units.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/cover_image.dart';
import '../../../../core/matrix/media_gallery_group.dart';
import '../../../../core/matrix/media_size.dart';
import '../../../../core/ui/media_pill.dart';
import '../../../../core/ui/zuno_colors.dart';
import '../../../../core/ui/zuno_theme.dart';
import '../../data/composed_media.dart';
import '../../data/pending_attachment_send.dart';
import '../media_viewer/media_hero.dart';
import 'pending_attachment_tile.dart';

const mediaInset = 4.0;

const mediaRadius = ZunoRadius.medium;

const _tallestMediaRatio = 9 / 16;

const _widestMediaRatio = 16 / 9;

double? mediaAspectRatio(int? width, int? height) {
  final size = mediaSize(width, height);
  if (size == null) return null;
  return (size.$1 / size.$2).clamp(_tallestMediaRatio, _widestMediaRatio);
}

Widget _videoBubbleMedia(Event event, PendingAttachmentSend? pending) {
  final preview = pending?.previewBytes;
  if (preview != null) return MediaImage.memory(preview);
  if (pending != null && pending.width != null && pending.height != null) {
    return const AspectRatioPlaceholder();
  }
  return attachmentThumbnail(
    event,
    placeholder: const AspectRatioPlaceholder(),
  );
}

Widget _metaOverMedia(Widget meta) => Positioned(
  right: 6,
  bottom: 6,
  child: MediaPill(size: MediaPillSize.small, child: meta),
);

class GalleryMessage extends StatelessWidget {
  final List<Event> events;
  final List<FailedMediaSend> failed;
  final void Function(FailedMediaSend) onRetry;
  final PendingAttachmentSend? pendingSend;
  final Widget mediaMeta;
  final void Function(Event event) onOpen;

  const GalleryMessage({
    super.key,
    required this.events,
    required this.failed,
    required this.onRetry,
    required this.pendingSend,
    required this.mediaMeta,
    required this.onOpen,
  });

  List<_GalleryEntry> get _entries {
    final entries = <_GalleryEntry>[
      for (final event in events) _SentEntry(event),
      for (final item in failed) _FailedEntry(item),
    ];
    entries.sort((a, b) => a.index.compareTo(b.index));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final layout = galleryTileLayout(entries.length);
    const gap = 2.0;
    final screenWidth = MediaQuery.sizeOf(context).width;

    Widget tileAt(int i, {required double shownAt}) => switch (entries[i]) {
      _FailedEntry(:final failed) => GalleryFailedThumbnail(
        failed: failed,
        onRetry: onRetry,
        shownAt: shownAt,
      ),
      _SentEntry(:final event) => _GalleryThumbnail(
        event: event,
        overflow: i == layout.visible - 1 ? layout.overflow : 0,
        shownAt: shownAt,
        pendingSend: pendingSend,
        onOpen: () => onOpen(event),
      ),
    };

    final rows = <Widget>[];
    var i = 0;
    while (i < layout.visible) {
      if (layout.visible - i == 1) {
        rows.add(
          AspectRatio(aspectRatio: 2, child: tileAt(i, shownAt: screenWidth)),
        );
        i += 1;
      } else {
        rows.add(
          Row(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: tileAt(i, shownAt: screenWidth / 2),
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: tileAt(i + 1, shownAt: screenWidth / 2),
                ),
              ),
            ],
          ),
        );
        i += 2;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(mediaRadius),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: gap),
                rows[r],
              ],
            ],
          ),
          _metaOverMedia(mediaMeta),
        ],
      ),
    );
  }
}

sealed class _GalleryEntry {
  final int index;

  const _GalleryEntry(this.index);
}

class _SentEntry extends _GalleryEntry {
  final Event event;

  _SentEntry(this.event) : super(galleryGroupOf(event)?.index ?? 0);
}

class _FailedEntry extends _GalleryEntry {
  final FailedMediaSend failed;

  _FailedEntry(this.failed) : super(failed.index);
}

class _GalleryThumbnail extends StatelessWidget {
  final Event event;
  final int overflow;
  final double shownAt;
  final PendingAttachmentSend? pendingSend;
  final VoidCallback onOpen;

  const _GalleryThumbnail({
    required this.event,
    required this.overflow,
    required this.shownAt,
    required this.pendingSend,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pending = pendingSend?.eventId == event.eventId ? pendingSend : null;
    return GestureDetector(
      onTap: pending != null ? null : onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          pending?.previewBytes != null
              ? MediaImage.memory(pending!.previewBytes!, shownAt: shownAt)
              : ThumbnailHero(
                  event: event,
                  child: attachmentThumbnail(
                    event,
                    placeholder: Container(
                      color: colors.surfaceContainerHighest,
                    ),
                    shownAt: shownAt,
                  ),
                ),
          if (event.messageType == MessageTypes.Video && pending == null)
            const Center(
              child: Icon(
                Icons.play_circle_outline,
                size: 36,
                color: onMediaColor,
              ),
            ),
          if (pending != null)
            ColoredBox(
              color: mediaScrimColor,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: onMediaColor,
                    value: pending.progress,
                  ),
                ),
              ),
            ),
          if (overflow > 0)
            ColoredBox(
              color: mediaScrimColor,
              child: Center(
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    color: onMediaColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class GalleryFailedThumbnail extends StatelessWidget {
  final FailedMediaSend failed;
  final void Function(FailedMediaSend) onRetry;
  final double? shownAt;

  const GalleryFailedThumbnail({
    super.key,
    required this.failed,
    required this.onRetry,
    this.shownAt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photo = switch (failed) {
      FailedComposedSend(media: ComposedImage(:final path)) => path,
      _ => null,
    };
    return GestureDetector(
      onTap: () => onRetry(failed),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            MediaImage.file(photo, shownAt: shownAt)
          else
            ColoredBox(color: colors.surfaceContainerHighest),
          ColoredBox(
            color: mediaScrimColor,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.refresh_outlined, color: onMediaColor),
                const SizedBox(height: 2),
                Text(
                  context.l10n.commonRetry,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: onMediaColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImageMessage extends StatelessWidget {
  final Event event;
  final PendingAttachmentSend? pendingSend;
  final Widget mediaMeta;
  final bool showTimeOverlay;
  final void Function(Event event) onOpen;

  const ImageMessage({
    super.key,
    required this.event,
    this.pendingSend,
    required this.mediaMeta,
    required this.showTimeOverlay,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final pending = pendingSend;
    final aspectRatio = mediaAspectRatio(event.mediaWidth, event.mediaHeight);
    return _MediaBubbleBody(
      aspectRatio: aspectRatio,
      pending: pending,
      onTap: pending != null ? null : () => onOpen(event),
      media: Stack(
        children: [
          Positioned.fill(
            child: pending?.previewBytes != null
                ? MediaImage.memory(pending!.previewBytes!)
                : ThumbnailHero(
                    event: event,
                    child: attachmentThumbnail(
                      event,
                      placeholder: const AspectRatioPlaceholder(),
                    ),
                  ),
          ),
          if (showTimeOverlay) _metaOverMedia(mediaMeta),
        ],
      ),
    );
  }
}

class VideoMessage extends StatelessWidget {
  final Event event;
  final PendingAttachmentSend? pendingSend;
  final Widget mediaMeta;
  final bool showTimeOverlay;
  final void Function(Event event) onOpen;

  const VideoMessage({
    super.key,
    required this.event,
    this.pendingSend,
    required this.mediaMeta,
    required this.showTimeOverlay,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final pending = pendingSend;
    final aspectRatio = mediaAspectRatio(
      pending?.width ?? event.mediaWidth,
      pending?.height ?? event.mediaHeight,
    );
    final duration = (pending == null && showTimeOverlay)
        ? event.mediaDuration
        : null;
    return _MediaBubbleBody(
      aspectRatio: aspectRatio,
      pending: pending,
      onTap: pending != null ? null : () => onOpen(event),
      media: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ThumbnailHero(
              event: event,
              enabled: pending == null,
              child: _videoBubbleMedia(event, pending),
            ),
          ),
          if (pending == null)
            Container(
              decoration: const BoxDecoration(
                color: mediaScrimColor,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.play_arrow,
                color: onMediaColor,
                size: 32,
              ),
            ),
          if (duration != null)
            Positioned(
              left: 6,
              bottom: 6,
              child: MediaPill(
                size: MediaPillSize.small,
                child: Text(formatDuration(duration)),
              ),
            ),
          if (showTimeOverlay) _metaOverMedia(mediaMeta),
        ],
      ),
    );
  }
}

class _MediaBubbleBody extends StatelessWidget {
  final Widget media;
  final double? aspectRatio;
  final VoidCallback? onTap;
  final PendingAttachmentSend? pending;

  const _MediaBubbleBody({
    required this.media,
    required this.aspectRatio,
    required this.onTap,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final pending = this.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(mediaRadius),
            child: aspectRatio != null
                ? AspectRatio(aspectRatio: aspectRatio!, child: media)
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: media,
                  ),
          ),
        ),
        if (pending != null) ...[
          const SizedBox(height: 4),
          AttachmentProgressBar(
            label: pending.progressLabel(context.l10n),
            progress: pending.progress,
          ),
        ],
      ],
    );
  }
}

class AspectRatioPlaceholder extends StatelessWidget {
  const AspectRatioPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}
