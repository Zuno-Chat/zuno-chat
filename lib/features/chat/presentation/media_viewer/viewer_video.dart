import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/cached_attachment_image.dart';
import '../../../../core/ui/failure_notice.dart';
import '../../../../core/ui/frosted_surface.dart';
import '../../../../core/ui/zuno_motion.dart';
import 'media_hero.dart';
import 'video_playback.dart';

class ViewerVideo extends StatelessWidget {
  final Event event;
  final Object? heroTag;
  final VideoPlayback? playback;
  final bool controlsVisible;
  final VoidCallback onPlay;

  const ViewerVideo({
    required this.event,
    this.heroTag,
    required this.playback,
    required this.controlsVisible,
    required this.onPlay,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final playback = this.playback;
    if (playback == null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _Poster(event: event, heroTag: heroTag),
          _CenterButton(
            icon: Icons.play_arrow_rounded,
            tooltip: context.l10n.matrixPlay,
            onPressed: onPlay,
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        if (playback.error != null) {
          return Center(
            child: FailureNotice(
              message: context.l10n.matrixVideoLoadFailed,
              onRetry: playback.start,
            ),
          );
        }
        final controller = playback.controller;
        if (controller == null) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _Poster(event: event, heroTag: heroTag),
              const CircularProgressIndicator(),
            ],
          );
        }
        final playing = playback.playing;
        return Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: MediaHero(tag: heroTag, child: VideoPlayer(controller)),
              ),
            ),
            if (!playing || controlsVisible)
              _CenterButton(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: playing
                    ? context.l10n.chatMediaPause
                    : context.l10n.matrixPlay,
                onPressed: playback.togglePlay,
              ),
          ],
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  final Event event;
  final Object? heroTag;

  const _Poster({required this.event, required this.heroTag});

  @override
  Widget build(BuildContext context) => ViewerFrame(
    event: event,
    child: MediaHero(
      tag: heroTag,
      child: CachedAttachmentImage(
        event: event,
        thumbnail: true,
        fit: BoxFit.contain,
      ),
    ),
  );
}

class _CenterButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _CenterButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => FrostedSurface(
    circle: true,
    child: IconButton(
      iconSize: 40,
      padding: const EdgeInsets.all(12),
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
    ),
  );
}
