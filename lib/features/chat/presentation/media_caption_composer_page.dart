import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'image_caption_composer_page.dart' show ComposedImage;
import 'preview_decode_width.dart';
import 'send_icon.dart';
import 'video_caption_composer_page.dart' show ComposedVideo;

sealed class PickedMedia {
  final String name;
  const PickedMedia({required this.name});
}

class PickedImage extends PickedMedia {
  final Uint8List bytes;
  const PickedImage({required super.name, required this.bytes});
}

class PickedVideo extends PickedMedia {
  final String path;
  const PickedVideo({required super.name, required this.path});
}

sealed class ComposedMedia {
  const ComposedMedia();
}

class ComposedImageResult extends ComposedMedia {
  final ComposedImage image;
  const ComposedImageResult(this.image);
}

class ComposedVideoResult extends ComposedMedia {
  final ComposedVideo video;
  const ComposedVideoResult(this.video);
}

class MediaCaptionComposerPage extends StatefulWidget {
  final List<PickedMedia> items;

  const MediaCaptionComposerPage({required this.items, super.key});

  @override
  State<MediaCaptionComposerPage> createState() =>
      _MediaCaptionComposerPageState();
}

class _MediaCaptionComposerPageState extends State<MediaCaptionComposerPage> {
  late final List<PickedMedia> _items;
  late final List<TextEditingController> _captionControllers;
  late final List<VideoPlayerController?> _videoControllers;
  late final List<Future<void>?> _videoInitFutures;
  final _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _captionControllers = List.generate(
      _items.length,
      (_) => TextEditingController(),
    );
    _videoControllers = [
      for (final item in _items)
        item is PickedVideo
            ? VideoPlayerController.file(File(item.path))
            : null,
    ];
    _videoInitFutures = [
      for (final controller in _videoControllers) controller?.initialize(),
    ];
  }

  @override
  void dispose() {
    for (final controller in _captionControllers) {
      controller.dispose();
    }
    for (final controller in _videoControllers) {
      controller?.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _removeCurrent() {
    if (_items.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _captionControllers.removeAt(_page).dispose();
      _videoControllers.removeAt(_page)?.dispose();
      _videoInitFutures.removeAt(_page);
      _items.removeAt(_page);
      if (_page >= _items.length) _page = _items.length - 1;
    });
  }

  ComposedMedia _composeItem(int i) {
    final caption = _captionControllers[i].text.trim();
    switch (_items[i]) {
      case PickedImage(:final bytes, :final name):
        return ComposedImageResult(
          ComposedImage(bytes: bytes, name: name, caption: caption),
        );
      case PickedVideo(:final path, :final name):
        final controller = _videoControllers[i]!;
        final size = controller.value.size;
        return ComposedVideoResult(
          ComposedVideo(
            path: path,
            name: name,
            caption: caption,
            width: size.width > 0 ? size.width.round() : null,
            height: size.height > 0 ? size.height.round() : null,
            durationMs: controller.value.duration.inMilliseconds,
          ),
        );
    }
  }

  void _send() {
    final result = [for (var i = 0; i < _items.length; i++) _composeItem(i)];
    Navigator.of(context).pop(result);
  }

  void _togglePlay(VideoPlayerController controller) {
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _items.length > 1;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          multiple ? '${_page + 1} of ${_items.length}' : 'Add a caption',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove this item',
            onPressed: _removeCurrent,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _items.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, i) => _buildPage(i),
              ),
            ),
            if (multiple)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofillHints: null,
                      controller: _captionControllers[_page],
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
                    tooltip: multiple ? 'Send all' : 'Send',
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

  Widget _buildPage(int i) {
    final item = _items[i];
    if (item is PickedImage) {
      return InteractiveViewer(
        child: Center(
          child: Image.memory(
            item.bytes,
            cacheWidth: previewDecodeWidth(context),
          ),
        ),
      );
    }
    final controller = _videoControllers[i]!;
    return FutureBuilder<void>(
      future: _videoInitFutures[i],
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: GestureDetector(
            onTap: () => _togglePlay(controller),
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
