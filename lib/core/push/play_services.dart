import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';

enum PlayServicesAvailability { available, updateRequired, unavailable }

class PlayServicesProbe {
  @visibleForTesting
  PlayServicesProbe({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  static final PlayServicesProbe instance = PlayServicesProbe();

  static const _channel = MethodChannel('zuno/play_services');

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<PlayServicesAvailability> check() async {
    if (!_capabilities.playServices) {
      return PlayServicesAvailability.unavailable;
    }
    try {
      final name = await _channel.invokeMethod<String>('checkPlayServices');
      return switch (name) {
        'AVAILABLE' => PlayServicesAvailability.available,
        'UPDATE_REQUIRED' => PlayServicesAvailability.updateRequired,
        _ => PlayServicesAvailability.unavailable,
      };
    } catch (e) {
      debugPrint('zuno/push: Play Services probe failed ($e)');
      return PlayServicesAvailability.unavailable;
    }
  }

  Future<void> requestFix() async {
    if (!_capabilities.playServices) return;
    try {
      await _channel.invokeMethod<void>('fixPlayServices');
    } catch (e) {
      debugPrint('zuno/push: Play Services fix refused ($e)');
    }
  }
}
