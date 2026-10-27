import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import '../ui/failure_notice.dart';
import 'cached_attachment_image.dart';

class ViewerPhoto extends StatelessWidget {
  final Event event;

  const ViewerPhoto({required this.event, super.key});

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    child: Center(
      child: CachedAttachmentImage(
        event: event,
        thumbnail: false,
        progress: const CircularProgressIndicator(),
        failure: (retry) => FailureNotice(
          message: context.l10n.matrixPhotoDidNotLoad,
          onRetry: retry,
        ),
      ),
    ),
  );
}
