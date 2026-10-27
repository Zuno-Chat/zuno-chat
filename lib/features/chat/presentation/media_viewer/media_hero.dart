import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../../../../core/matrix/media_size.dart';
import '../../../../core/ui/zuno_motion.dart';

Object mediaHeroTag(Route<dynamic> route, Event event) =>
    (route, event.eventId);

class ThumbnailHero extends StatelessWidget {
  final Event event;
  final bool enabled;
  final Widget child;

  const ThumbnailHero({
    required this.event,
    required this.child,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final route = enabled ? ModalRoute.of(context) : null;
    return MediaHero(
      tag: route == null ? null : mediaHeroTag(route, event),
      keepsSourceVisible: true,
      child: child,
    );
  }
}

class ViewerFrame extends StatelessWidget {
  final Event event;
  final Widget child;

  const ViewerFrame({required this.event, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final size = mediaSize(
      event.infoMap.tryGet<int>('w'),
      event.infoMap.tryGet<int>('h'),
    );
    if (size == null) return SizedBox.expand(child: child);
    return Center(
      child: AspectRatio(aspectRatio: size.$1 / size.$2, child: child),
    );
  }
}
