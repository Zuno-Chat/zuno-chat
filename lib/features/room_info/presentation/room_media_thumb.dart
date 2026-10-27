import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/human_units.dart';
import '../../../core/matrix/cover_image.dart';
import '../../../core/ui/zuno_colors.dart';
import '../../chat/presentation/media_viewer/media_hero.dart';

class RoomMediaThumb extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const RoomMediaThumb({required this.event, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = event.messageType == MessageTypes.Video;
    final durationMs = isVideo ? event.infoMap.tryGet<int>('duration') : null;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, cell) => ThumbnailHero(
                event: event,
                child: attachmentThumbnail(
                  event,
                  placeholder: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  shownAt: cell.maxWidth,
                ),
              ),
            ),
            if (isVideo)
              Positioned(
                left: 6,
                bottom: 6,
                child: _VideoBadge(durationMs: durationMs),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoBadge extends StatelessWidget {
  final int? durationMs;

  const _VideoBadge({required this.durationMs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationMs = this.durationMs;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
      decoration: BoxDecoration(
        color: mediaScrimColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow, size: 14, color: onMediaColor),
          if (durationMs != null)
            Text(
              formatDuration(Duration(milliseconds: durationMs)),
              style: theme.textTheme.labelSmall?.copyWith(color: onMediaColor),
            ),
        ],
      ),
    );
  }
}
