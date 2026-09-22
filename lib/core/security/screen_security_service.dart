import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/calls');

class ScreenSecurityService {
  ScreenSecurityService._();
  static final instance = ScreenSecurityService._();

  Future<void> setPreventScreenshots(bool enabled) async {
    try {
      await _channel.invokeMethod('setPreventScreenshots', {
        'enabled': enabled,
      });
    } on MissingPluginException catch (_) {}
  }
}
