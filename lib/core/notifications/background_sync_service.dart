import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/background_sync');

class BackgroundSyncService {
  BackgroundSyncService._();
  static final instance = BackgroundSyncService._();

  Future<void> start() => _channel.invokeMethod('startBackgroundSyncService');

  Future<void> stop() => _channel.invokeMethod('stopBackgroundSyncService');

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
      false;

  Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod('requestIgnoreBatteryOptimizations');

  Future<bool> isPackageIgnoringBatteryOptimizations(String package) async =>
      await _channel.invokeMethod<bool>(
        'isPackageIgnoringBatteryOptimizations',
        {'package': package},
      ) ??
      false;

  Future<void> openAppSettings(String package) =>
      _channel.invokeMethod('openAppSettings', {'package': package});

  Future<bool> isBackgroundDataRestricted() async =>
      await _channel.invokeMethod<bool>('isBackgroundDataRestricted') ?? false;

  Future<void> openBackgroundDataSettings() =>
      _channel.invokeMethod('openBackgroundDataSettings');
}
