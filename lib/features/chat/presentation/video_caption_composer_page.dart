import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/composed_video.dart';
import 'send_icon.dart';

export '../data/composed_video.dart';

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

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _send() {
    final size = _controller.value.size;
    Navigator.of(context).pop(
      ComposedVideo(
        path: widget.path,
        name: widget.name,
        caption: _captionController.text.trim(),
        width: size.width > 0 ? size.width.round() : null,
        height: size.height > 0 ? size.height.round() : null,
        durationMs: _controller.value.duration.inMilliseconds,
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
              child: FutureBuilder<void>(
                future: _initializeFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Center(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(_controller),
                            AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) =>
                                  _controller.value.isPlaying
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofillHints: null,
                      controller: _captionController,
                      decoration: const InputDecoration(
                        hintText: 'Add a caption…',
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const SendIcon(),
                    tooltip: 'Send',
                    onPressed: _send,
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
