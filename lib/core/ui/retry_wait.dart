import 'dart:async';

import 'package:flutter/widgets.dart';

mixin RetryWait<T extends StatefulWidget> on State<T> {
  Timer? _retryTimer;

  bool get waitingToRetry => _retryTimer != null;

  void holdRetriesFor(Duration? wait, {required VoidCallback whenOver}) {
    if (wait == null) return;
    _retryTimer?.cancel();
    setState(() {
      _retryTimer = Timer(
        wait,
        () => setState(() {
          _retryTimer = null;
          whenOver();
        }),
      );
    });
  }

  void releaseRetryHold() {
    final timer = _retryTimer;
    if (timer == null) return;
    timer.cancel();
    setState(() => _retryTimer = null);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
