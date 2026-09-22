import 'dart:async';

import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/calls');

const sensitiveClipboardLifetime = Duration(seconds: 90);

class SensitiveClipboard {
  SensitiveClipboard._();
  static final instance = SensitiveClipboard._();

  Timer? _clearTimer;

  Future<void> copy(String text) async {
    try {
      await _channel.invokeMethod('copySensitive', {'text': text});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      await Clipboard.setData(ClipboardData(text: text));
    }
    _clearTimer?.cancel();
    _clearTimer = Timer(sensitiveClipboardLifetime, () {
      unawaited(_clearIfMatches(text));
    });
  }

  Future<void> _clearIfMatches(String text) async {
    try {
      await _channel.invokeMethod('clearClipboardIfMatches', {'text': text});
    } on MissingPluginException catch (_) {} on PlatformException catch (_) {}
  }

  void cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
