import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zuno/core/security/recovery_code_file.dart';

import '../../helpers/fake_attachments.dart';

const _code =
    'acorn blew celery diesel elbow fever glow harp idle jolt kiwi lamp';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('decodeRecoveryCodeFile', () {
    test('reads back the file Zuno saves', () {
      expect(decodeRecoveryCodeFile(encodeRecoveryCodeFile(_code)), _code);
    });

    test('reads a file a Windows editor saved', () {
      final edited = [0xEF, 0xBB, 0xBF, ...utf8.encode('$_code\r\n')];

      expect(decodeRecoveryCodeFile(_bytes(edited)), _code);
    });

    test('keeps a key or phrase from another app as written', () {
      const key = 'EsTc 7Ldb ofvA 1Ufx';

      expect(decodeRecoveryCodeFile(_bytes(utf8.encode('  $key\n'))), key);
    });

    test('an empty file holds no code', () {
      expect(decodeRecoveryCodeFile(_bytes(utf8.encode(' \n\t'))), isNull);
    });

    test('a file that is not text holds no code', () {
      expect(decodeRecoveryCodeFile(_bytes([0xFF, 0xD8, 0xFF, 0xE0])), isNull);
    });

    test('text with control bytes holds no code', () {
      expect(
        decodeRecoveryCodeFile(_bytes([...utf8.encode('acorn'), 0, 1, 2])),
        isNull,
      );
    });

    test('a file far bigger than a code holds no code', () {
      final big = utf8.encode('$_code ' * 100);

      expect(decodeRecoveryCodeFile(_bytes(big)), isNull);
    });
  });

  group('readPickedRecoveryCodeFile', () {
    late Directory temporaryRoot;

    setUp(() {
      temporaryRoot = Directory.systemTemp.createTempSync('picker_copies');
      addTearDown(() => temporaryRoot.deleteSync(recursive: true));
    });

    FakePickedFile pickerCopy(Uint8List bytes, {Object? readError}) {
      final copy = File(p.join(temporaryRoot.path, 'zuno-recovery-code.txt'))
        ..writeAsBytesSync(bytes);
      return FakePickedFile(
        'zuno-recovery-code.txt',
        bytes,
        path: copy.path,
        readError: readError,
      );
    }

    test('reads the code and deletes the picker copy', () async {
      final picked = pickerCopy(encodeRecoveryCodeFile(_code));

      final code = await readPickedRecoveryCodeFile(
        picked,
        temporaryRoots: [temporaryRoot],
      );

      expect(code, _code);
      expect(File(picked.path!).existsSync(), isFalse);
    });

    test('deletes the picker copy of a file without a code', () async {
      final picked = pickerCopy(_bytes([0xFF, 0xD8, 0xFF, 0xE0]));

      final code = await readPickedRecoveryCodeFile(
        picked,
        temporaryRoots: [temporaryRoot],
      );

      expect(code, isNull);
      expect(File(picked.path!).existsSync(), isFalse);
    });

    test('deletes the picker copy when reading fails', () async {
      final picked = pickerCopy(
        encodeRecoveryCodeFile(_code),
        readError: const FileSystemException('gone'),
      );

      await expectLater(
        readPickedRecoveryCodeFile(picked, temporaryRoots: [temporaryRoot]),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(picked.path!).existsSync(), isFalse);
    });

    test('reads a code whose size the picker could not report', () async {
      final bytes = encodeRecoveryCodeFile(_code);
      final copy = pickerCopy(bytes);
      final picked = _UnsizedPickedFile(copy.path!, () => Stream.value(bytes));

      final code = await readPickedRecoveryCodeFile(
        picked,
        temporaryRoots: [temporaryRoot],
      );

      expect(code, _code);
      expect(File(copy.path!).existsSync(), isFalse);
    });

    test('stops reading a file far bigger than a code', () async {
      final copy = pickerCopy(_bytes([0x61]));
      var chunksRead = 0;
      Stream<Uint8List> fourMegabytes() async* {
        for (var i = 0; i < 4096; i++) {
          chunksRead++;
          yield Uint8List(1024)..fillRange(0, 1024, 0x61);
        }
      }

      final code = await readPickedRecoveryCodeFile(
        _UnsizedPickedFile(copy.path!, fourMegabytes),
        temporaryRoots: [temporaryRoot],
      );

      expect(code, isNull);
      expect(chunksRead, lessThan(8));
      expect(File(copy.path!).existsSync(), isFalse);
    });
  });
}

final class _UnsizedPickedFile extends PlatformFile {
  _UnsizedPickedFile(String path, this._chunks) : uri = Uri.file(path);

  final Stream<Uint8List> Function() _chunks;

  @override
  final Uri uri;

  @override
  String get name => p.basename(uri.toFilePath());

  @override
  XFile get xFile => XFile(uri.toFilePath());

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() async => null;

  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(await _chunks().expand((chunk) => chunk).toList());

  @override
  Stream<Uint8List> readAsByteStream() => _chunks();
}
