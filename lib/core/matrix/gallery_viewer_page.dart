import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import 'attachment_action_buttons.dart';
import 'cached_attachment_image.dart';
import 'image_caption.dart';
import 'video_viewer_page.dart';
import 'viewer_photo.dart';

class GalleryViewerPage extends StatefulWidget {
  final List<Event> events;
  final int initialIndex;

  const GalleryViewerPage({
    required this.events,
    this.initialIndex = 0,
    super.key,
  });

  @override
  State<GalleryViewerPage> createState() => _GalleryViewerPageState();
}

class _GalleryViewerPageState extends State<GalleryViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = imageCaption(widget.events[_page]);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          context.l10n.matrixGalleryPosition(_page + 1, widget.events.length),
        ),
        actions: [AttachmentActionButtons(event: widget.events[_page])],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.events.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, i) =>
                  _GalleryPage(event: widget.events[i]),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _GalleryPage extends StatelessWidget {
  final Event event;

  const _GalleryPage({required this.event});

  @override
  Widget build(BuildContext context) {
    if (event.messageType != MessageTypes.Video) {
      return ViewerPhoto(event: event);
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(child: CachedAttachmentImage(event: event, thumbnail: true)),
        IconButton(
          iconSize: 64,
          color: Colors.white,
          icon: const Icon(Icons.play_circle_outline),
          tooltip: context.l10n.matrixPlay,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VideoViewerPage(event: event)),
          ),
        ),
      ],
    );
  }
}
