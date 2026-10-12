import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/platform_capabilities.dart';

const _channel = MethodChannel('zuno/share_out');

Future<void> shareFiles(
  List<XFile> files, {
  PlatformCapabilities? capabilities,
}) async {
  if (!(capabilities ?? ambientCapabilities).nativeFileShare) {
    await SharePlus.instance.share(ShareParams(files: files));
    return;
  }
  await _channel.invokeMethod<void>('shareFiles', {
    'paths': [for (final file in files) file.path],
    'mimeTypes': [for (final file in files) file.mimeType],
  });
}
