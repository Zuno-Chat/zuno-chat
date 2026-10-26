import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../../core/files/file_system.dart';
import '../../../../core/format/human_units.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/cached_attachment_image.dart';
import '../../../../core/matrix/gallery_viewer_page.dart';
import '../../../../core/matrix/image_viewer_page.dart';
import '../../../../core/matrix/media_gallery_group.dart';
import '../../../../core/matrix/video_viewer_page.dart';
import '../../data/pending_attachment_send.dart';
import '../preview_decode_width.dart';
import 'pending_attachment_tile.dart';

const mediaInset = 4.0;

const mediaRadius = 16.0;

const _tallestMediaRatio = 9 / 16;

const _widestMediaRatio = 16 / 9;

double? mediaAspectRatio(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return (width / height).clamp(_tallestMediaRatio, _widestMediaRatio);
}

Widget _mediaOverlayBadge(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );
}

class MediaImage extends StatelessWidget {
  final ImageProvider image;
  final double? shownAt;

  MediaImage.memory(Uint8List bytes, {this.shownAt, super.key})
    : image = MemoryImage(bytes);

  MediaImage.file(String path, {this.shownAt, super.key})
    : image = FileImage(fileSystem.file(path));

  @override
  Widget build(BuildContext context) => Image(
    image: _CoverDecode(image, decodeWidth(context, shownAt: shownAt)),
    fit: BoxFit.cover,
  );
}

const _widestCoverBox = 2;

class _CoverDecode extends ImageProvider<(Object, int)> {
  final ImageProvider image;
  final int side;

  const _CoverDecode(this.image, this.side);

  @override
  Future<(Object, int)> obtainKey(ImageConfiguration configuration) =>
      image.obtainKey(configuration).then((key) => (key, side));

  @override
  ImageStreamCompleter loadImage(
    (Object, int) key,
    ImageDecoderCallback decode,
  ) =>
      image.loadImage(
        key.$1,
        (buffer, {getTargetSize}) => decode(buffer, getTargetSize: _coverSize),
      )..addEphemeralErrorListener(
        (_, _) => scheduleMicrotask(
          () => PaintingBinding.instance.imageCache.evict(key),
        ),
      );

  ui.TargetImageSize _coverSize(int width, int height) {
    final scale = [
      1.0,
      side / math.min(width, height),
      side * _widestCoverBox / math.max(width, height),
    ].reduce(math.min);
    return ui.TargetImageSize(
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverDecode && other.image == image && other.side == side;

  @override
  int get hashCode => Object.hash(image, side);
}

Widget _videoBubbleMedia(Event event, PendingAttachmentSend? pending) {
  final preview = pending?.previewBytes;
  if (preview != null) return MediaImage.memory(preview);
  if (pending != null && pending.width != null && pending.height != null) {
    return const AspectRatioPlaceholder();
  }
  return attachmentThumbnail(
    event,
    placeholder: _thumbnailSpinner,
    noThumbnail: const AspectRatioPlaceholder(),
  );
}

Widget attachmentThumbnail(
  Event event, {
  required Widget placeholder,
  Widget? noThumbnail,
  double? shownAt,
}) {
  return CachedAttachmentImage(
    event: event,
    thumbnail: true,
    placeholder: placeholder,
    noThumbnail: noThumbnail,
    builder: (context, bytes) => MediaImage.memory(bytes, shownAt: shownAt),
  );
}

const _thumbnailSpinner = SizedBox(
  height: 120,
  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
);

Widget _mediaMetaBadge(Widget meta) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(10),
    ),
    child: meta,
  );
}

class GalleryMessage extends StatelessWidget {
  final List<Event> events;
  final List<FailedMediaSend> failed;
  final void Function(FailedMediaSend) onRetry;
  final PendingAttachmentSend? pendingSend;
  final Widget mediaMeta;

  const GalleryMessage({
    super.key,
    required this.events,
    required this.failed,
    required this.onRetry,
    required this.pendingSend,
    required this.mediaMeta,
  });

  List<_GalleryEntry> get _entries {
    final entries = <_GalleryEntry>[
      for (final event in events)
        _GalleryEntry(event: event, index: galleryGroupOf(event)?.index ?? 0),
      for (final item in failed) _GalleryEntry(failed: item, index: item.index),
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

    Widget tileAt(int i, {required double shownAt}) => _GalleryThumbnail(
      entry: entries[i],
      overflow: i == layout.visible - 1 ? layout.overflow : 0,
      shownAt: shownAt,
      pendingSend: pendingSend,
      onRetry: onRetry,
      onOpen: () {
        final event = entries[i].event;
        if (event == null) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GalleryViewerPage(
              events: events,
              initialIndex: events.indexOf(event),
            ),
          ),
        );
      },
    );

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
          Positioned(right: 6, bottom: 6, child: _mediaMetaBadge(mediaMeta)),
        ],
      ),
    );
  }
}

class _GalleryEntry {
  final Event? event;
  final FailedMediaSend? failed;
  final int index;

  const _GalleryEntry({this.event, this.failed, required this.index});
}

class _GalleryThumbnail extends StatelessWidget {
  final _GalleryEntry entry;
  final int overflow;
  final double shownAt;
  final PendingAttachmentSend? pendingSend;
  final void Function(FailedMediaSend) onRetry;
  final VoidCallback onOpen;

  const _GalleryThumbnail({
    required this.entry,
    required this.overflow,
    required this.shownAt,
    required this.pendingSend,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = entry.failed;
    if (failed != null) {
      return GalleryFailedThumbnail(
        failed: failed,
        onRetry: onRetry,
        shownAt: shownAt,
      );
    }

    final event = entry.event!;
    final pending = pendingSend?.eventId == event.eventId ? pendingSend : null;
    return GestureDetector(
      onTap: pending != null ? null : onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          pending?.previewBytes != null
              ? MediaImage.memory(pending!.previewBytes!, shownAt: shownAt)
              : attachmentThumbnail(
                  event,
                  placeholder: Container(color: colors.surfaceContainerHighest),
                  shownAt: shownAt,
                ),
          if (event.messageType == MessageTypes.Video && pending == null)
            const Center(
              child: Icon(
                Icons.play_circle_outline,
                size: 36,
                color: Colors.white,
              ),
            ),
          if (pending != null)
            ColoredBox(
              color: Colors.black45,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                    value: pending.progress,
                  ),
                ),
              ),
            ),
          if (overflow > 0)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    color: Colors.white,
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
    final photo = failed.photo;
    return GestureDetector(
      onTap: () => onRetry(failed),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            MediaImage.file(photo.path, shownAt: shownAt)
          else
            ColoredBox(color: colors.surfaceContainerHighest),
          ColoredBox(
            color: Colors.black54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.refresh_outlined, color: Colors.white),
                const SizedBox(height: 2),
                Text(
                  context.l10n.commonRetry,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.white),
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

  const ImageMessage({
    super.key,
    required this.event,
    this.pendingSend,
    required this.mediaMeta,
    required this.showTimeOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final pending = pendingSend;
    final aspectRatio = mediaAspectRatio(
      event.infoMap.tryGet<int>('w'),
      event.infoMap.tryGet<int>('h'),
    );
    return _MediaBubbleBody(
      aspectRatio: aspectRatio,
      pending: pending,
      onTap: pending != null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ImageViewerPage(event: event)),
            ),
      media: Stack(
        children: [
          Positioned.fill(
            child: pending?.previewBytes != null
                ? MediaImage.memory(pending!.previewBytes!)
                : attachmentThumbnail(event, placeholder: _thumbnailSpinner),
          ),
          if (showTimeOverlay)
            Positioned(right: 6, bottom: 6, child: _mediaMetaBadge(mediaMeta)),
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

  const VideoMessage({
    super.key,
    required this.event,
    this.pendingSend,
    required this.mediaMeta,
    required this.showTimeOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final pending = pendingSend;
    final aspectRatio = mediaAspectRatio(
      pending?.width ?? event.infoMap.tryGet<int>('w'),
      pending?.height ?? event.infoMap.tryGet<int>('h'),
    );
    final durationMs = (pending == null && showTimeOverlay)
        ? event.infoMap.tryGet<int>('duration')
        : null;
    return _MediaBubbleBody(
      aspectRatio: aspectRatio,
      pending: pending,
      onTap: pending != null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VideoViewerPage(event: event)),
            ),
      media: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: _videoBubbleMedia(event, pending)),
          if (pending == null)
            Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          if (durationMs != null)
            Positioned(
              left: 6,
              bottom: 6,
              child: _mediaOverlayBadge(
                formatDuration(Duration(milliseconds: durationMs)),
              ),
            ),
          if (showTimeOverlay)
            Positioned(right: 6, bottom: 6, child: _mediaMetaBadge(mediaMeta)),
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
