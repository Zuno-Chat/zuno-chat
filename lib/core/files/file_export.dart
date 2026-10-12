import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/files');

Future<bool> exportFile({
  required String name,
  required Uint8List bytes,
  required String mimeType,
  String? dialogTitle,
  PlatformCapabilities? capabilities,
}) async {
  if ((capabilities ?? ambientCapabilities).nativeSensitiveFileExport) {
    final saved = await _channel.invokeMethod<bool>('exportSensitiveFile', {
      'name': name,
      'bytes': bytes,
    });
    return saved ?? false;
  }
  return await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: name,
        mimeType: mimeType,
        bytes: bytes,
      ) !=
      null;
}

Future<bool> exportFileAt(String path, {required String mimeType}) async =>
    await _channel.invokeMethod<bool>('exportFile', {
      'path': path,
      'mimeType': mimeType,
    }) ??
    false;
