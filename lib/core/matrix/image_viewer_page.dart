import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'attachment_action_buttons.dart';
import 'viewer_photo.dart';

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
      body: ViewerPhoto(event: event),
    );
  }
}
