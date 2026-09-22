import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import 'attachment_action_buttons.dart';
import 'attachment_cache.dart';

class VideoViewerPage extends StatefulWidget {
  final Event event;

  const VideoViewerPage({required this.event, super.key});

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final file = await fetchCachedAttachmentFile(
        attachmentCacheKey(widget.event, thumbnail: false),
        () async => (await widget.event.downloadAndDecryptAttachment()).bytes,
      );
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller..play());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [AttachmentActionButtons(event: widget.event)],
      ),
      body: Center(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Text(
        'Video did not load. Try again.',
        style: const TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(controller),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => controller.value.isPlaying
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.play_arrow,
                      size: 72,
                      color: Colors.white70,
                    ),
            ),
            VideoProgressIndicator(controller, allowScrubbing: true),
          ],
        ),
      ),
    );
  }
}
