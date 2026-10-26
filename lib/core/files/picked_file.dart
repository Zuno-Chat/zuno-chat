import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../errors/best_effort.dart';
import 'file_system.dart';

Future<void> discardTemporaryCopy(
  String path, {
  List<Directory>? temporaryRoots,
}) async {
  final copy = fileSystem.file(path);
  if (!copy.existsSync()) return;
  await runBestEffort(() async {
    final roots = temporaryRoots ?? await _appTemporaryRoots();
    bool insideTemporary(String entry) =>
        roots.any((root) => p.isWithin(root.path, entry)) &&
        !roots.any((root) => p.equals(root.path, entry));
    if (!insideTemporary(path)) return;
    copy.deleteSync();
    final folder = copy.parent;
    if (insideTemporary(folder.path) && folder.listSync().isEmpty) {
      folder.deleteSync();
    }
  }, label: 'discard a temporary copy');
}

Future<void> discardPickedCopy(
  PlatformFile file, {
  List<Directory>? temporaryRoots,
}) async {
  final path = file.path;
  if (path == null) return;
  await discardTemporaryCopy(path, temporaryRoots: temporaryRoots);
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
  fileSystem.systemTempDirectory,
  await temporaryDirectory(),
];
