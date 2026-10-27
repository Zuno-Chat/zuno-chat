import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import 'cached_attachment_image.dart';
import 'viewer_status.dart';

class ViewerPhoto extends StatelessWidget {
  final Event event;

  const ViewerPhoto({required this.event, super.key});

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    child: Center(
      child: CachedAttachmentImage(
        event: event,
        thumbnail: false,
        progress: viewerProgress,
        failure: (retry) => ViewerNotice(
          text: context.l10n.matrixPhotoDidNotLoad,
          retry: retry,
        ),
      ),
    ),
  );
}
