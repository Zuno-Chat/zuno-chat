import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/matrix/auth_error_message.dart';

mixin RetryWait<T extends StatefulWidget> on State<T> {
  Timer? _retryTimer;

  bool get waitingToRetry => _retryTimer != null;

  void holdRetriesFor(Object error, {required VoidCallback whenOver}) {
    final wait = retryWaitFor(error);
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

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
