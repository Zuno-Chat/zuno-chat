import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/calls');

class ScreenSecurityService {
  @visibleForTesting
  ScreenSecurityService({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = ScreenSecurityService();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<void> setPreventScreenshots(bool enabled) async {
    if (!_capabilities.screenSecurity) return;
    try {
      await _channel.invokeMethod('setPreventScreenshots', {
        'enabled': enabled,
      });
    } on MissingPluginException catch (e, s) {
      reportCaught('set screenshot prevention', e, s);
    }
  }
}
