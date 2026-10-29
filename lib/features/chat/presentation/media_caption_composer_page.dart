import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/files/file_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/ui/page_dots.dart';
import '../../../core/ui/zuno_colors.dart';
import '../data/composed_media.dart';
import 'caption_bar.dart';
import 'preview_decode_width.dart';

export '../data/composed_media.dart';

sealed class PickedMedia {
  final String path;
  final String name;
  const PickedMedia({required this.path, required this.name});
}

class PickedImage extends PickedMedia {
  const PickedImage({required super.path, required super.name});
}

class PickedVideo extends PickedMedia {
  const PickedVideo({required super.path, required super.name});
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
  final _seenVideos = <PickedVideo, VideoPlayerValue>{};
  PickedVideo? _shownVideo;
  VideoPlayerController? _player;
  Future<void>? _playerReady;
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
    _showPlayerFor(_items[_page]);
  }

  @override
  void dispose() {
    for (final controller in _captionControllers) {
      controller.dispose();
    }
    _player?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _showPlayerFor(PickedMedia item) {
    if (identical(item, _shownVideo)) return;
    _releasePlayer();
    if (item is! PickedVideo) return;
    final player = VideoPlayerController.file(fileSystem.file(item.path));
    _shownVideo = item;
    _player = player;
    _playerReady = reportFailureOf(player.initialize(), label: 'preview video')
      ..ignore();
  }

  void _releasePlayer() {
    final shown = _shownVideo;
    final player = _player;
    if (shown != null && player != null && player.value.isInitialized) {
      _seenVideos[shown] = player.value;
    }
    player?.dispose();
    _shownVideo = null;
    _player = null;
    _playerReady = null;
  }

  VideoPlayerValue _valueOf(PickedVideo video) {
    final live = identical(video, _shownVideo) ? _player?.value : null;
    if (live != null && live.isInitialized) return live;
    return _seenVideos[video] ?? const VideoPlayerValue.uninitialized();
  }

  void _removeCurrent() {
    if (_items.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _captionControllers.removeAt(_page).dispose();
      final removed = _items.removeAt(_page);
      if (identical(removed, _shownVideo)) _releasePlayer();
      _seenVideos.remove(removed);
      if (_page >= _items.length) _page = _items.length - 1;
      _showPlayerFor(_items[_page]);
    });
  }

  ComposedMedia _composeItem(int i) {
    final caption = _captionControllers[i].text.trim();
    switch (_items[i]) {
      case PickedImage(:final path, :final name):
        return ComposedImage(path: path, name: name, caption: caption);
      case final PickedVideo video:
        final value = _valueOf(video);
        return ComposedVideo(
          path: video.path,
          name: video.name,
          caption: caption,
          width: value.size.width > 0 ? value.size.width.round() : null,
          height: value.size.height > 0 ? value.size.height.round() : null,
          durationMs: value.isInitialized
              ? value.duration.inMilliseconds
              : null,
        );
    }
  }

  void _send() {
    final result = [for (var i = 0; i < _items.length; i++) _composeItem(i)];
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _items.length > 1;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          multiple
              ? l10n.chatCaptionPageOf(_page + 1, _items.length)
              : l10n.chatCaptionTitle,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: _items.every((item) => item is PickedImage)
                ? l10n.chatRemovePhoto
                : l10n.chatRemoveItem,
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
                onPageChanged: (page) => setState(() {
                  _page = page;
                  _showPlayerFor(_items[page]);
                }),
                itemBuilder: (context, i) => _buildPage(i),
              ),
            ),
            if (multiple)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: PageDots(count: _items.length, current: _page),
              ),
            CaptionBar(
              controller: _captionControllers[_page],
              sendTooltip: multiple ? l10n.chatSendAll : l10n.commonSend,
              onSend: _send,
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
          child: Image.file(
            fileSystem.file(item.path),
            cacheWidth: previewDecodeWidth(context),
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, size: 64),
          ),
        ),
      );
    }
    final player = _player;
    if (!identical(item, _shownVideo) || player == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _VideoPreview(controller: player, loading: _playerReady);
  }
}

class _VideoPreview extends StatelessWidget {
  final VideoPlayerController controller;
  final Future<void>? loading;

  const _VideoPreview({required this.controller, required this.loading});

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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.l10n.chatVideoNoPreview,
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
                            color: onMediaVariantColor,
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
