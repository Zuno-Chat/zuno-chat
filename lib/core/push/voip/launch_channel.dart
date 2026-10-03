import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../../platform/platform_capabilities.dart';

const launchChannel = MethodChannel('zuno/launch');

enum WakeReason { ring, action }

class LaunchChannel {
  const LaunchChannel({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  bool get _enabled => (_injectedCapabilities ?? ambientCapabilities).voipRing;

  Future<WakeReason?> takeWakeReason() async =>
      WakeReason.values.asNameMap()[await _invoke<String>('takeWakeReason')];

  Future<List<String>> takeDiagnostics() async => [
    for (final line in await _invoke<List<Object?>>('takeDiagnostics') ?? [])
      if (line is String) line,
  ];

  Future<T?> _invoke<T>(String method) async {
    if (!_enabled) return null;
    try {
      return await launchChannel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('zuno/launch: $method failed (${e.code})');
      return null;
    }
  }
}
