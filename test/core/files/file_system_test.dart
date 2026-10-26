import 'dart:io' as io;

import 'package:fake_async/fake_async.dart';
import 'package:file/file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:zuno/core/files/file_system.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = fileSystem.systemTempDirectory.createTempSync('zuno_fs');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  String inRoot(String name) => p.join(root.path, name);

  test('tests reach the real disk, and a write and read finish in fake '
      'time', () {
    fakeAsync((async) {
      final file = fileSystem.file(inRoot('note.txt'));
      String? read;

      file
          .writeAsString('hello')
          .then((_) => file.readAsString())
          .then((text) => read = text);
      async.flushMicrotasks();

      expect(read, 'hello');
      expect(io.File(file.path).readAsStringSync(), 'hello');
    });
  });

  test('a listing, a partial read and a link finish in fake time too', () {
    fakeAsync((async) {
      fileSystem.file(inRoot('a.bin')).writeAsBytesSync([1, 2, 3, 4]);
      List<String>? names;
      List<int>? middle;
      String? target;

      root
          .list()
          .map((entity) => p.basename(entity.path))
          .toList()
          .then((listed) => names = listed);
      fileSystem
          .file(inRoot('a.bin'))
          .openRead(1, 3)
          .expand((chunk) => chunk)
          .toList()
          .then((bytes) => middle = bytes);
      fileSystem
          .link(inRoot('a.link'))
          .create(inRoot('a.bin'))
          .then((link) => link.target())
          .then((linked) => target = linked);
      async.flushMicrotasks();

      expect(names, ['a.bin']);
      expect(middle, [2, 3]);
      expect(target, inRoot('a.bin'));
    });
  });

  test('a missing file fails the way dart:io fails', () async {
    await expectLater(
      fileSystem.file(inRoot('gone')).readAsBytes(),
      throwsA(isA<io.PathNotFoundException>()),
    );
    await expectLater(
      fileSystem.file(inRoot('gone')).openRead().toList(),
      throwsA(isA<io.PathNotFoundException>()),
    );
  });

  test('an API that would wait on the real disk fails loudly', () {
    final file = fileSystem.file(inRoot('note.txt'));

    expect(file.openWrite, throwsUnsupportedError);
    expect(file.open, throwsUnsupportedError);
    expect(root.watch, throwsUnsupportedError);
  });

  test(
    'directory lookups put the platform folders on the file system',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        _pathProvider,
        (call) async => switch (call.method) {
          'getTemporaryDirectory' => inRoot('temp'),
          'getApplicationCacheDirectory' => inRoot('cache'),
          'getApplicationSupportDirectory' => inRoot('support'),
          _ => null,
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(_pathProvider, null),
      );

      final folders = [
        await temporaryDirectory(),
        await applicationCacheDirectory(),
        await applicationSupportDirectory(),
      ];

      expect(folders.map((folder) => folder.path), [
        inRoot('temp'),
        inRoot('cache'),
        inRoot('support'),
      ]);
      expect(
        folders.map((folder) => folder.fileSystem),
        everyElement(fileSystem),
      );
    },
  );
}
