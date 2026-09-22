import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'attachment_action_buttons.dart';
import 'cached_attachment_image.dart';

class ImageViewerPage extends StatelessWidget {
  final Event event;

  const ImageViewerPage({required this.event, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [AttachmentActionButtons(event: event)],
      ),
      body: CachedAttachmentImage(
        event: event,
        thumbnail: false,
        placeholder: const Center(child: CircularProgressIndicator()),
        builder: (context, bytes) =>
            InteractiveViewer(child: Center(child: Image.memory(bytes))),
      ),
    );
  }
}
