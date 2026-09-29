import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/platform_capabilities.dart';

const _extensionsByMimetype = {
  'video/mp4': '.mp4',
  'video/quicktime': '.mov',
  'video/x-m4v': '.m4v',
  'video/3gpp': '.3gp',
};

String _videoExtension(String? mimetype, String? fileName) {
  final known = _extensionsByMimetype[mimetype?.toLowerCase()];
  if (known != null) return known;
  final fromName = fileName == null ? '' : p.extension(fileName);
  return fromName.isEmpty ? '.mp4' : fromName.toLowerCase();
}

Future<File> playableVideoFile(
  File cached, {
  required String? mimetype,
  required String? fileName,
  required PlatformCapabilities capabilities,
  Directory? linkDirectory,
}) async {
  if (!capabilities.playerNeedsMediaType) return cached;
  final dir = linkDirectory ?? await getTemporaryDirectory();
  final link = Link(
    p.join(
      dir.path,
      '${p.basename(cached.path)}${_videoExtension(mimetype, fileName)}',
    ),
  );
  if (await link.exists()) await link.delete();
  await link.create(cached.absolute.path);
  return File(link.path);
}
