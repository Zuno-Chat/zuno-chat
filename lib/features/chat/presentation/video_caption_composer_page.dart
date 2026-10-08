import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/composed_video.dart';
import 'caption_bar.dart';

export '../data/composed_video.dart';

ComposedVideo composeVideo({
  required String path,
  required String name,
  required String caption,
  required VideoPlayerValue value,
}) => ComposedVideo(
  path: path,
  name: name,
  caption: caption,
  width: value.size.width > 0 ? value.size.width.round() : null,
  height: value.size.height > 0 ? value.size.height.round() : null,
  durationMs: value.isInitialized ? value.duration.inMilliseconds : null,
);

class ComposerVideoPreview extends StatelessWidget {
  final VideoPlayerController controller;
  final Future<void>? loading;

  const ComposerVideoPreview({
    required this.controller,
    required this.loading,
    super.key,
  });

  void _togglePlay() {
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !controller.value.isInitialized) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This video cannot be previewed.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return Center(
          child: GestureDetector(
            onTap: _togglePlay,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(controller),
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => controller.value.isPlaying
                        ? const SizedBox.shrink()
                        : const Icon(
                            Icons.play_arrow,
                            size: 64,
                            color: Colors.white70,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class VideoCaptionComposerPage extends StatefulWidget {
  final String path;
  final String name;

  const VideoCaptionComposerPage({
    required this.path,
    required this.name,
    super.key,
  });

  @override
  State<VideoCaptionComposerPage> createState() =>
      _VideoCaptionComposerPageState();
}

class _VideoCaptionComposerPageState extends State<VideoCaptionComposerPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeFuture;
  final _captionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _initializeFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.of(context).pop(
      composeVideo(
        path: widget.path,
        name: widget.name,
        caption: _captionController.text.trim(),
        value: _controller.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a caption')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ComposerVideoPreview(
                controller: _controller,
                loading: _initializeFuture,
              ),
            ),
            CaptionBar(controller: _captionController, onSend: _send),
          ],
        ),
      ),
    );
  }
}
