import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zuno/core/files/picked_file.dart';

import '../../helpers/fake_attachments.dart';

void main() {
  late Directory temporaryRoot;
  late Directory elsewhere;

  setUp(() {
    temporaryRoot = Directory.systemTemp.createTempSync('picker_copies');
    elsewhere = Directory.systemTemp.createTempSync('user_files');
    addTearDown(() {
      temporaryRoot.deleteSync(recursive: true);
      elsewhere.deleteSync(recursive: true);
    });
  });

  FakePickedFile pickedAt(Directory directory) {
    final file = File(p.join(directory.path, 'notes.txt'))
      ..writeAsBytesSync([1]);
    return FakePickedFile(
      'notes.txt',
      Uint8List.fromList([1]),
      path: file.path,
    );
  }

  test('deletes a copy in temporary storage', () async {
    final picked = pickedAt(temporaryRoot);

    await discardPickedCopy(picked, temporaryRoots: [temporaryRoot]);

    expect(File(picked.path!).existsSync(), isFalse);
  });

  test('never deletes a file outside temporary storage', () async {
    final picked = pickedAt(elsewhere);

    await discardPickedCopy(picked, temporaryRoots: [temporaryRoot]);

    expect(File(picked.path!).existsSync(), isTrue);
  });

  test('a path that climbs out of temporary storage is kept', () async {
    final original = pickedAt(elsewhere);
    final climbing = p.join(
      temporaryRoot.path,
      '..',
      p.basename(elsewhere.path),
      'notes.txt',
    );

    await discardPickedCopy(
      FakePickedFile('notes.txt', Uint8List.fromList([1]), path: climbing),
      temporaryRoots: [temporaryRoot],
    );

    expect(File(original.path!).existsSync(), isTrue);
  });
}
