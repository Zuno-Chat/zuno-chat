import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/background_sync');

class BackgroundSyncService {
  @visibleForTesting
  BackgroundSyncService({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;
  static final instance = BackgroundSyncService();

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<void> start() async {
    if (!_capabilities.foregroundSyncService) return;
    await _channel.invokeMethod('startBackgroundSyncService');
  }

  Future<void> stop() async {
    if (!_capabilities.foregroundSyncService) return;
    await _channel.invokeMethod('stopBackgroundSyncService');
  }
}
