import 'package:flutter/material.dart';

import '../../../core/files/file_system.dart';
import '../../../core/l10n/l10n.dart';
import '../data/composed_image.dart';
import 'caption_bar.dart';
import 'preview_decode_width.dart';

export '../data/composed_image.dart';

class ImageCaptionComposerPage extends StatefulWidget {
  final List<({String path, String name})> images;

  const ImageCaptionComposerPage({required this.images, super.key});

  @override
  State<ImageCaptionComposerPage> createState() =>
      _ImageCaptionComposerPageState();
}

class _ImageCaptionComposerPageState extends State<ImageCaptionComposerPage> {
  late final List<({String path, String name})> _images;
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
          path: _images[i].path,
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          multiple
              ? l10n.chatCaptionPageOf(_page + 1, _images.length)
              : l10n.chatCaptionTitle,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.chatRemovePhoto,
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
                    child: Image.file(
                      fileSystem.file(_images[i].path),
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
              sendTooltip: multiple ? l10n.chatSendAll : l10n.commonSend,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}
