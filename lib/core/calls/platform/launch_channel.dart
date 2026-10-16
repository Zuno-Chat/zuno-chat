import 'package:flutter/services.dart';

import '../../errors/caught_errors.dart';
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

  Future<T?> _invoke<T>(String method) async {
    if (!_enabled) return null;
    try {
      return await launchChannel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, s) {
      reportCaught('launch $method', e.code, s);
      return null;
    }
  }
}
