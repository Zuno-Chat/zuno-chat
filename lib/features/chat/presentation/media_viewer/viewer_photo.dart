import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/matrix/cached_attachment_image.dart';
import '../../../../core/ui/failure_notice.dart';
import '../../../../core/ui/zuno_motion.dart';
import 'media_hero.dart';

const _zoomedScale = 2.5;
const _maxScale = 5.0;

class ViewerPhoto extends StatefulWidget {
  final Event event;
  final Object? heroTag;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  const ViewerPhoto({
    required this.event,
    this.heroTag,
    required this.onTap,
    required this.onZoomChanged,
    super.key,
  });

  @override
  State<ViewerPhoto> createState() => _ViewerPhotoState();
}

class _ViewerPhotoState extends State<ViewerPhoto>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final _zoomAnimation = AnimationController(
    vsync: this,
    duration: ZunoDurations.standard,
  )..addListener(_stepZoom);
  Matrix4Tween? _zoomTween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_followZoom);
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _followZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  void _stepZoom() {
    final tween = _zoomTween;
    if (tween == null) return;
    _transform.value = tween.transform(
      Curves.easeOut.transform(_zoomAnimation.value),
    );
  }

  void _toggleZoom() {
    final Matrix4 target;
    if (_zoomed) {
      target = Matrix4.identity();
    } else {
      final point = _doubleTapAt;
      target = Matrix4.identity()
        ..translateByDouble(
          -point.dx * (_zoomedScale - 1),
          -point.dy * (_zoomedScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_zoomedScale, _zoomedScale, 1, 1);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
      return;
    }
    _zoomTween = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _zoomAnimation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = CachedAttachmentImage(
      event: widget.event,
      thumbnail: false,
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
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: _zoomed,
        maxScale: _maxScale,
        child: ViewerFrame(
          event: widget.event,
          child: MediaHero(tag: widget.heroTag, child: image),
        ),
      ),
    );
  }
}
