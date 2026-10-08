import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/live_location_viewing.dart';
import '../../../core/ui/visible_in_front.dart';

class LiveLocationWatchScope extends ConsumerStatefulWidget {
  final String roomId;
  final Widget child;

  const LiveLocationWatchScope({
    required this.roomId,
    required this.child,
    super.key,
  });

  @override
  ConsumerState<LiveLocationWatchScope> createState() =>
      _LiveLocationWatchScopeState();
}

class _LiveLocationWatchScopeState extends ConsumerState<LiveLocationWatchScope>
    with VisibleInFront {
  LiveLocationWatch? _watch;

  @override
  void onVisibleInFrontChanged() {
    if (visibleInFront && _watch == null) {
      _watch = ref.read(liveLocationViewingProvider).watch(widget.roomId);
    } else if (!visibleInFront && _watch != null) {
      _watch!.close();
      _watch = null;
    }
  }

  @override
  void didUpdateWidget(LiveLocationWatchScope old) {
    super.didUpdateWidget(old);
    if (old.roomId == widget.roomId) return;
    _watch?.close();
    _watch = null;
    onVisibleInFrontChanged();
  }

  @override
  void dispose() {
    _watch?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
