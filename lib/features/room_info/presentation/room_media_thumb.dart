import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/human_units.dart';
import '../../../core/matrix/cover_image.dart';
import '../../../core/matrix/media_size.dart';
import '../../../core/ui/media_pill.dart';
import '../../../core/ui/zuno_theme.dart';
import '../../chat/presentation/media_viewer/media_hero.dart';

class RoomMediaThumb extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const RoomMediaThumb({required this.event, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = event.messageType == MessageTypes.Video;
    final duration = isVideo ? event.mediaDuration : null;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZunoRadius.small),
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
                child: MediaPill(
                  size: MediaPillSize.small,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: MediaPillSize.small.gap,
                    children: [
                      const Icon(Icons.play_arrow),
                      if (duration != null) Text(formatDuration(duration)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
