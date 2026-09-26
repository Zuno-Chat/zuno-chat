import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';

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

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_capabilities.batteryExemption) return true;
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_capabilities.batteryExemption) return;
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  Future<bool> isPackageIgnoringBatteryOptimizations(String package) async {
    if (!_capabilities.batteryExemption) return true;
    return await _channel.invokeMethod<bool>(
          'isPackageIgnoringBatteryOptimizations',
          {'package': package},
        ) ??
        false;
  }

  Future<void> openAppSettings(String package) async {
    if (!_capabilities.batteryExemption) return;
    await _channel.invokeMethod('openAppSettings', {'package': package});
  }

  Future<bool> isBackgroundDataRestricted() async {
    if (!_capabilities.backgroundDataRestriction) return false;
    return await _channel.invokeMethod<bool>('isBackgroundDataRestricted') ??
        false;
  }

  Future<void> openBackgroundDataSettings() async {
    if (!_capabilities.backgroundDataRestriction) return;
    await _channel.invokeMethod('openBackgroundDataSettings');
  }

  Future<bool> hasAutostartSettings() async {
    if (!_capabilities.autostartSettings) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAutostartSettings') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openAutostartSettings() async {
    if (!_capabilities.autostartSettings) return;
    await _channel.invokeMethod('openAutostartSettings');
  }
}
