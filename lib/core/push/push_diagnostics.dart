import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

class PushDiagnostics {
  PushDiagnostics({
    PlatformCapabilities? capabilities,
    this.channel = const MethodChannel('zuno/push_diag'),
  }) : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;
  final MethodChannel channel;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<Map<Object?, Object?>?> rawSnapshot() async {
    if (!_capabilities.pushDiagnostics) return null;
    try {
      final raw = await channel.invokeMethod<Object?>('snapshot');
      return raw is Map ? raw : null;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, s) {
      reportCaught('push diagnostics snapshot', e.code, s);
      return null;
    }
  }
}
