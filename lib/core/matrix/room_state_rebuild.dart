import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

mixin RoomStateRebuild<T extends StatefulWidget> on State<T> {
  StreamSubscription<({String roomId, StrippedStateEvent state})>?
  _roomStateSub;
  bool _rebuildPending = false;

  Client get roomStateClient;

  @override
  void initState() {
    super.initState();
    _roomStateSub = roomStateClient.onRoomState.stream.listen((_) {
      if (_rebuildPending || !mounted) return;
      _rebuildPending = true;
      scheduleMicrotask(() {
        _rebuildPending = false;
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _roomStateSub?.cancel();
    super.dispose();
  }
}
