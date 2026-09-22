import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'attachment_action_buttons.dart';
import 'cached_attachment_image.dart';
import 'image_caption.dart';
import 'video_viewer_page.dart';

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
        title: Text('${_page + 1} of ${widget.events.length}'),
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
    final isVideo = event.messageType == MessageTypes.Video;
    final image = CachedAttachmentImage(
      event: event,
      thumbnail: isVideo,
      placeholder: const Center(child: CircularProgressIndicator()),
      builder: (context, bytes) => Image.memory(bytes),
    );
    if (!isVideo) {
      return InteractiveViewer(child: Center(child: image));
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(child: image),
        IconButton(
          iconSize: 64,
          color: Colors.white,
          icon: const Icon(Icons.play_circle_outline),
          tooltip: 'Play',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VideoViewerPage(event: event)),
          ),
        ),
      ],
    );
  }
}
