import 'package:flutter/services.dart';

import '../navigation/held_broadcast.dart';
import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/shortcuts');

final _openRooms = HeldBroadcast<String>();

Stream<String> get onOpenRoomShortcut => _openRooms.stream;

bool _hasShortcuts(PlatformCapabilities? capabilities) =>
    (capabilities ?? ambientCapabilities).homeScreenShortcuts;

bool _opensRoomsFromNative(PlatformCapabilities? capabilities) =>
    (capabilities ?? ambientCapabilities).nativeRoomOpens;

void initHomeScreenShortcutChannel({PlatformCapabilities? capabilities}) {
  if (!_opensRoomsFromNative(capabilities)) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'openRoom') _openRooms.add(call.arguments as String);
    return null;
  });
}

Future<String?> takeLaunchRoomShortcut({
  PlatformCapabilities? capabilities,
}) async {
  if (!_opensRoomsFromNative(capabilities)) return null;
  return _channel.invokeMethod<String>('takeLaunchRoomId');
}

Future<bool> pinRoomShortcut({
  required String roomId,
  required String label,
  Uint8List? iconBytes,
  PlatformCapabilities? capabilities,
}) async {
  if (!_hasShortcuts(capabilities)) return false;
  final result = await _channel.invokeMethod<bool>('pinShortcut', {
    'id': 'room_$roomId',
    'label': label,
    'roomId': roomId,
    'iconBytes': iconBytes,
  });
  return result ?? false;
}
