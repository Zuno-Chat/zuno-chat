import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
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

  String copyAt(Directory directory) {
    final copy = File(p.join(directory.path, 'notes.txt'))
      ..writeAsBytesSync([1]);
    return copy.path;
  }

  test('deletes a copy in temporary storage', () async {
    final copy = copyAt(temporaryRoot);

    await discardTemporaryCopy(copy, temporaryRoots: [temporaryRoot]);

    expect(File(copy).existsSync(), isFalse);
    expect(temporaryRoot.existsSync(), isTrue);
  });

  test('deletes the folder made for the copy', () async {
    final folder = Directory(p.join(temporaryRoot.path, 'pick'))..createSync();

    await discardTemporaryCopy(copyAt(folder), temporaryRoots: [temporaryRoot]);

    expect(folder.existsSync(), isFalse);
    expect(temporaryRoot.existsSync(), isTrue);
  });

  test('never deletes a temporary root inside another', () async {
    final inner = Directory(p.join(temporaryRoot.path, 'cache'))..createSync();

    await discardTemporaryCopy(
      copyAt(inner),
      temporaryRoots: [temporaryRoot, inner],
    );

    expect(inner.existsSync(), isTrue);
  });

  test('keeps a folder that still holds another copy', () async {
    final folder = Directory(p.join(temporaryRoot.path, 'pick'))..createSync();
    final other = File(p.join(folder.path, 'other.txt'))..writeAsBytesSync([2]);

    await discardTemporaryCopy(copyAt(folder), temporaryRoots: [temporaryRoot]);

    expect(other.existsSync(), isTrue);
  });

  test('never deletes a file outside temporary storage', () async {
    final original = copyAt(elsewhere);

    await discardTemporaryCopy(original, temporaryRoots: [temporaryRoot]);

    expect(File(original).existsSync(), isTrue);
  });

  test('a path that climbs out of temporary storage is kept', () async {
    final original = copyAt(elsewhere);
    final climbing = p.join(
      temporaryRoot.path,
      '..',
      p.basename(elsewhere.path),
      'notes.txt',
    );

    await discardTemporaryCopy(climbing, temporaryRoots: [temporaryRoot]);

    expect(File(original).existsSync(), isTrue);
  });

  test('a copy already gone is ignored', () async {
    await discardTemporaryCopy(
      p.join(temporaryRoot.path, 'gone.txt'),
      temporaryRoots: [temporaryRoot],
    );

    expect(temporaryRoot.existsSync(), isTrue);
  });

  test('a file picker copy is discarded the same way', () async {
    final copy = copyAt(temporaryRoot);

    await discardPickedCopy(
      FakePickedFile('notes.txt', Uint8List.fromList([1]), path: copy),
      temporaryRoots: [temporaryRoot],
    );

    expect(File(copy).existsSync(), isFalse);
  });

  group('trackPickerCopy', () {
    test('reports a copy from the picker signal until the pick ends', () async {
      final states = <bool>[];

      final picked = await trackPickerCopy((onFileLoading) async {
        onFileLoading(FilePickerStatus.picking);
        return 'notes.txt';
      }, onCopying: states.add);

      expect(picked, 'notes.txt');
      expect(states, [true, false]);
    });

    test('a done signal before the pick ends reports the end once', () async {
      final states = <bool>[];

      await trackPickerCopy((onFileLoading) async {
        onFileLoading(FilePickerStatus.picking);
        onFileLoading(FilePickerStatus.done);
      }, onCopying: states.add);

      expect(states, [true, false]);
    });

    test('a pick that fails mid-copy still ends the copy', () async {
      final states = <bool>[];

      await expectLater(
        trackPickerCopy<void>((onFileLoading) async {
          onFileLoading(FilePickerStatus.picking);
          throw PlatformException(code: 'unknown_path');
        }, onCopying: states.add),
        throwsA(isA<PlatformException>()),
      );
      expect(states, [true, false]);
    });

    test('a cancelled pick reports nothing', () async {
      final states = <bool>[];

      await trackPickerCopy((_) async => null, onCopying: states.add);

      expect(states, isEmpty);
    });
  });
}
