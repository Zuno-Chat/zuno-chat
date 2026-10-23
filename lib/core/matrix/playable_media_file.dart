import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/platform_capabilities.dart';

const _extensionOverrides = {
  'audio/opus': 'opus',
  'audio/wav': 'wav',
  'audio/x-m4a': 'm4a',
};

String _extension(String? mimetype, String? fileName, String fallback) {
  final type = mimetype?.toLowerCase();
  final known = type == null
      ? null
      : _extensionOverrides[type] ?? extensionFromMime(type);
  if (known != null) return '.$known';
  final fromName = fileName == null ? '' : p.extension(fileName);
  return fromName.isEmpty ? fallback : fromName.toLowerCase();
}

Future<File> playableMediaFile(
  File cached, {
  required String? mimetype,
  required String? fileName,
  required String fallbackExtension,
  required PlatformCapabilities capabilities,
  Directory? linkDirectory,
}) async {
  if (!capabilities.playerNeedsMediaType) return cached;
  final dir = linkDirectory ?? await getTemporaryDirectory();
  final link = Link(
    p.join(
      dir.path,
      '${p.basename(cached.path)}${_extension(mimetype, fileName, fallbackExtension)}',
    ),
  );
  if (await link.exists()) await link.delete();
  await link.create(cached.absolute.path);
  return File(link.path);
}
