import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/best_effort.dart';

Future<void> discardPickedCopy(
  PlatformFile file, {
  List<Directory>? temporaryRoots,
}) async {
  final path = file.path;
  if (path == null || !File(path).existsSync()) return;
  await runBestEffort(() async {
    final roots = temporaryRoots ?? await _appTemporaryRoots();
    if (roots.any((root) => p.isWithin(root.path, path))) {
      await File(path).delete();
    }
  }, label: 'discard picked copy');
}

Future<List<Directory>> _appTemporaryRoots() async => [
  Directory.systemTemp,
  await getTemporaryDirectory(),
];
