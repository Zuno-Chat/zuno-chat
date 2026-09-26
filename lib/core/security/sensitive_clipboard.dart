import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/calls');

const sensitiveClipboardLifetime = Duration(seconds: 90);

class SensitiveClipboard {
  @visibleForTesting
  SensitiveClipboard({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = SensitiveClipboard();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Timer? _clearTimer;

  Future<void> copy(String text) async {
    if (!_capabilities.sensitiveClipboard) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
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
    } on MissingPluginException catch (_) {
    } on PlatformException catch (_) {}
  }

  void cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
