import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';
import 'privacy_channel.dart';

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
  AppLifecycleListener? _clearOnResume;

  Future<void> copy(String text) async {
    if (!_capabilities.sensitiveClipboard) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    try {
      await privacyChannel.invokeMethod('copySensitive', {'text': text});
    } on MissingPluginException catch (e, s) {
      reportCaught('copy sensitive text', e, s);
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException catch (e, s) {
      reportCaught('copy sensitive text', e, s);
      await Clipboard.setData(ClipboardData(text: text));
    }
    cancelPendingClear();
    _clearTimer = Timer(sensitiveClipboardLifetime, () {
      unawaited(_clearIfMatches(text));
    });
  }

  Future<void> _clearIfMatches(String text) async {
    try {
      final unreadable = await privacyChannel.invokeMethod<bool>(
        'clearClipboardIfMatches',
        {'text': text},
      );
      if (unreadable == true) _clearOnNextResume(text);
    } on MissingPluginException catch (e, s) {
      reportCaught('clear the sensitive clipboard', e, s);
    } on PlatformException catch (e, s) {
      reportCaught('clear the sensitive clipboard', e, s);
    }
  }

  void _clearOnNextResume(String text) {
    _stopClearOnResume();
    _clearOnResume = AppLifecycleListener(
      onResume: () {
        _stopClearOnResume();
        unawaited(_clearIfMatches(text));
      },
    );
  }

  void _stopClearOnResume() {
    _clearOnResume?.dispose();
    _clearOnResume = null;
  }

  void cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _stopClearOnResume();
  }
}
