import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/media/attachments/cached_attachment_image.dart';
import '../../../../core/ui/failure_notice.dart';
import '../../../../core/ui/zoomable.dart';
import '../../../../core/ui/zuno_motion.dart';
import 'media_hero.dart';

class ViewerPhoto extends StatefulWidget {
  final Event event;
  final Object? heroTag;
  final VoidCallback onTap;

  const ViewerPhoto({
    required this.event,
    this.heroTag,
    required this.onTap,
    super.key,
  });

  @override
  State<ViewerPhoto> createState() => _ViewerPhotoState();
}

class _ViewerPhotoState extends State<ViewerPhoto> {
  bool _fullSize = false;

  ImageProvider _decoded(BuildContext context, ImageProvider attachment) {
    if (_fullSize) return attachment;
    final screen =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(
      attachment,
      width: screen.width.round(),
      height: screen.height.round(),
      policy: ResizeImagePolicy.fit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = CachedAttachmentImage(
      event: widget.event,
      thumbnail: false,
      image: _decoded,
      gaplessPlayback: true,
      fit: BoxFit.contain,
      progress: const CircularProgressIndicator(),
      failure: (retry) => Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: FailureNotice(
            message: context.l10n.matrixPhotoDidNotLoad,
            onRetry: retry,
          ),
        ),
      ),
    );
    return Zoomable(
      onTap: widget.onTap,
      onZoomChanged: (zoomed) {
        if (zoomed && !_fullSize) setState(() => _fullSize = true);
      },
      child: ViewerFrame(
        event: widget.event,
        child: MediaHero(tag: widget.heroTag, child: image),
      ),
    );
  }
}
