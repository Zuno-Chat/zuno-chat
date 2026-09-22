import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

enum PlayServicesAvailability {
  available,
  updateRequired,
  unavailable,
}

class PlayServicesProbe {
  PlayServicesProbe._();

  static final PlayServicesProbe instance = PlayServicesProbe._();

  static const _channel = MethodChannel('zuno/play_services');

  Future<PlayServicesAvailability> check() async {
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
    try {
      await _channel.invokeMethod<void>('fixPlayServices');
    } catch (e) {
      debugPrint('zuno/push: Play Services fix refused ($e)');
    }
  }
}
