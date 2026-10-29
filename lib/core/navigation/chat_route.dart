import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

final _rooms = Expando<String>('chat route room');

void markChatRoute(BuildContext context, String roomId) {
  final route = ModalRoute.of(context);
  if (route != null) _rooms[route] = roomId;
}

bool isChatRoute(Route<Object?>? route, String roomId) =>
    route != null && _rooms[route] == roomId;

bool chatInFront(AppLifecycleState? state) =>
    state == null || state == AppLifecycleState.resumed;

class OpenChatObserver extends NavigatorObserver with ChangeNotifier {
  final _routes = <Route<Object?>>[];
  late final AppLifecycleListener _lifecycle;
  String? _openRoomId;
  bool _refreshScheduled = false;

  OpenChatObserver() {
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _refresh());
  }

  String? get openRoomId => _openRoomId;

  String? _topChat() {
    if (!chatInFront(WidgetsBinding.instance.lifecycleState)) return null;
    for (final route in _routes.reversed) {
      final roomId = _rooms[route];
      if (roomId != null) return roomId;
    }
    return null;
  }

  void _refresh() {
    final roomId = _topChat();
    if (roomId == _openRoomId) return;
    _openRoomId = roomId;
    notifyListeners();
  }

  void _refreshAfterFrame() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _refreshScheduled = false;
        _refresh();
      })
      ..ensureVisualUpdate();
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _routes.add(route);
    _refreshAfterFrame();
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    _routes.remove(route);
    _refreshAfterFrame();
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    _routes.remove(route);
    _refreshAfterFrame();
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    final at = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute != null) {
      if (at < 0) {
        _routes.add(newRoute);
      } else {
        _routes[at] = newRoute;
      }
    } else if (at >= 0) {
      _routes.removeAt(at);
    }
    _refreshAfterFrame();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }
}
