import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'caption_bar.dart';
import 'preview_decode_width.dart';

class ComposedImage {
  final Uint8List bytes;
  final String name;
  final String caption;

  const ComposedImage({
    required this.bytes,
    required this.name,
    required this.caption,
  });
}

class ImageCaptionComposerPage extends StatefulWidget {
  final List<({Uint8List bytes, String name})> images;

  const ImageCaptionComposerPage({required this.images, super.key});

  @override
  State<ImageCaptionComposerPage> createState() =>
      _ImageCaptionComposerPageState();
}

class _ImageCaptionComposerPageState extends State<ImageCaptionComposerPage> {
  late final List<({Uint8List bytes, String name})> _images;
  late final List<TextEditingController> _captionControllers;
  final _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _images = List.of(widget.images);
    _captionControllers = List.generate(
      _images.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final controller in _captionControllers) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _removeCurrent() {
    if (_images.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _captionControllers.removeAt(_page).dispose();
      _images.removeAt(_page);
      if (_page >= _images.length) _page = _images.length - 1;
    });
  }

  void _send() {
    final result = [
      for (var i = 0; i < _images.length; i++)
        ComposedImage(
          bytes: _images[i].bytes,
          name: _images[i].name,
          caption: _captionControllers[i].text.trim(),
        ),
    ];
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _images.length > 1;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          multiple ? '${_page + 1} of ${_images.length}' : 'Add a caption',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove this photo',
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
                itemCount: _images.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, i) => InteractiveViewer(
                  child: Center(
                    child: Image.memory(
                      _images[i].bytes,
                      cacheWidth: previewDecodeWidth(context),
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, size: 64),
                    ),
                  ),
                ),
              ),
            ),
            if (multiple)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _images.length; i++)
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
            CaptionBar(
              controller: _captionControllers[_page],
              sendTooltip: multiple ? 'Send all' : 'Send',
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}
