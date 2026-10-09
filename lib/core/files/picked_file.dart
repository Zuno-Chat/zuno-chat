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
    bool insideTemporary(String entry) =>
        roots.any((root) => p.isWithin(root.path, entry)) &&
        !roots.any((root) => p.equals(root.path, entry));
    if (!insideTemporary(path)) return;
    File(path).deleteSync();
    final folder = File(path).parent;
    if (insideTemporary(folder.path) && folder.listSync().isEmpty) {
      folder.deleteSync();
    }
  }, label: 'discard picked copy');
}

Future<T> trackPickerCopy<T>(
  Future<T> Function(void Function(FilePickerStatus) onFileLoading) pick, {
  required void Function(bool copying) onCopying,
}) async {
  var copying = false;
  void report(bool next) {
    if (next == copying) return;
    copying = next;
    onCopying(next);
  }

  try {
    return await pick((status) => report(status == FilePickerStatus.picking));
  } finally {
    report(false);
  }
}

Future<List<Directory>> _appTemporaryRoots() async => [
  Directory.systemTemp,
  await getTemporaryDirectory(),
];
