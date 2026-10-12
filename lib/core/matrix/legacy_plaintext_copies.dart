import 'dart:io';

import 'package:path/path.dart' as p;

final _untrackedCopy = RegExp(r'^attachment_\d+$');

Future<void> removeLegacyPlaintextCopies(Directory temp) async {
  for (final folder in const ['handover', 'share_plus']) {
    final dir = Directory(p.join(temp.path, folder));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
  await for (final entry in temp.list()) {
    if (entry is File && _untrackedCopy.hasMatch(p.basename(entry.path))) {
      try {
        await entry.delete();
      } on PathNotFoundException {
        continue;
      }
    }
  }
}
