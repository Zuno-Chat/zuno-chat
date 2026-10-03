import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../../platform/platform_capabilities.dart';

const nseChannel = MethodChannel('zuno/nse');

class NseChannel {
  const NseChannel({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  bool get _enabled => (_injectedCapabilities ?? ambientCapabilities).voipRing;

  Future<String?> threadKey(String roomId) =>
      _invoke<String>('threadKey', {'room_id': roomId});

  Future<bool> writeMeta(String json) => _write('writeMeta', {'json': json});

  Future<bool> writeRoom(String roomId, String json) =>
      _write('writeRoom', {'room_id': roomId, 'json': json});

  Future<void> deleteRoom(String roomId) =>
      _invoke<void>('deleteRoom', {'room_id': roomId});

  Future<void> wipe() => _invoke<void>('wipe');

  Future<bool> _write(String method, Map<String, Object?> arguments) async {
    if (!_enabled) return false;
    try {
      await nseChannel.invokeMethod<void>(method, arguments);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('zuno/nse: $method failed (${e.code})');
      return false;
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_enabled) return null;
    try {
      return await nseChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('zuno/nse: $method failed (${e.code})');
      return null;
    }
  }
}
