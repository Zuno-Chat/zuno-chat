import 'package:flutter/material.dart';

import '../../../../core/ui/zuno_colors.dart';
import '../../../../core/ui/zuno_theme.dart';
import '../../data/pending_attachment_send.dart';
import '../message_bubble.dart';
import 'media_message.dart';

class AttachmentProgressBar extends StatelessWidget {
  final String label;
  final double? progress;

  const AttachmentProgressBar({
    super.key,
    required this.label,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            progress == null ? label : '$label ${(progress! * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: bubbleMuted(Theme.of(context), own: true)),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 4),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachmentPreview extends StatelessWidget {
  final PendingAttachmentSend pendingSend;

  const _PendingAttachmentPreview({required this.pendingSend});

  @override
  Widget build(BuildContext context) {
    final aspectRatio = mediaAspectRatio(pendingSend.width, pendingSend.height);
    final preview = pendingSend.previewBytes;
    final Widget media;
    if (preview != null) {
      media = Image.memory(preview, fit: BoxFit.cover);
    } else if (pendingSend.width != null && pendingSend.height != null) {
      media = const AspectRatioPlaceholder();
    } else {
      media = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(mediaRadius),
          child: aspectRatio != null
              ? AspectRatio(aspectRatio: aspectRatio, child: media)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: media,
                ),
        ),
        const SizedBox(height: 4),
        AttachmentProgressBar(
          label: pendingSend.progressLabel,
          progress: pendingSend.progress,
        ),
      ],
    );
  }
}

class _OwnMediaBubble extends StatelessWidget {
  final Widget child;

  const _OwnMediaBubble({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(
                width: MediaQuery.sizeOf(context).width * 2 / 3,
              ),
              child: Material(
                color: ZunoColors.of(context).bubbleOutgoing,
                borderRadius: BorderRadius.circular(ZunoRadius.large),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(mediaInset),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PendingAttachmentTile extends StatelessWidget {
  final PendingAttachmentSend pendingSend;

  const PendingAttachmentTile({super.key, required this.pendingSend});

  @override
  Widget build(BuildContext context) {
    return _OwnMediaBubble(
      child: _PendingAttachmentPreview(pendingSend: pendingSend),
    );
  }
}

class FailedGalleryTile extends StatelessWidget {
  final List<FailedMediaSend> failed;
  final void Function(FailedMediaSend) onRetry;

  const FailedGalleryTile({
    super.key,
    required this.failed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...failed]..sort((a, b) => a.index.compareTo(b.index));
    return _OwnMediaBubble(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AspectRatio(
                aspectRatio: 2,
                child: GalleryFailedThumbnail(failed: item, onRetry: onRetry),
              ),
            ),
          Text(
            failed.length == 1
                ? 'Not sent. Tap to try again.'
                : 'Not sent. Tap an item to try again.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
