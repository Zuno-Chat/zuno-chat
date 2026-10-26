import 'dart:io';

import 'package:path/path.dart' as p;

import '../files/file_system.dart';

final _untrackedCopy = RegExp(r'^attachment_\d+$');

Future<void> removeLegacyPlaintextCopies(Directory temp) async {
  final root = fileSystem.directory(temp);
  for (final folder in const ['handover', 'share_plus']) {
    final dir = fileSystem.directory(p.join(root.path, folder));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
  await for (final entry in root.list()) {
    if (entry is File && _untrackedCopy.hasMatch(p.basename(entry.path))) {
      try {
        await entry.delete();
      } on PathNotFoundException {
        continue;
      }
    }
  }
}
