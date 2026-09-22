import 'dart:async';

import 'package:flutter/services.dart';

const _channel = MethodChannel('zuno/shortcuts');

final _openRoomController = StreamController<String>.broadcast();

Stream<String> get onOpenRoomShortcut => _openRoomController.stream;

void initHomeScreenShortcutChannel() {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'openRoom') {
      _openRoomController.add(call.arguments as String);
    }
    return null;
  });
}

Future<String?> takeLaunchRoomShortcut() =>
    _channel.invokeMethod<String>('takeLaunchRoomId');

Future<bool> pinRoomShortcut({
  required String roomId,
  required String label,
  Uint8List? iconBytes,
}) async {
  final result = await _channel.invokeMethod<bool>('pinShortcut', {
    'id': 'room_$roomId',
    'label': label,
    'roomId': roomId,
    'iconBytes': iconBytes,
  });
  return result ?? false;
}
