import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zuno/core/matrix/legacy_plaintext_copies.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('legacy_copies'));
  tearDown(() => temp.deleteSync(recursive: true));

  File write(String path) => File(p.join(temp.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync('plaintext');

  test(
    'copies older builds left in the temporary folder are deleted',
    () async {
      write('handover/abc/photo.jpg');
      write('share_plus/photo.jpg');
      write('attachment_1728700000000000');

      await removeLegacyPlaintextCopies(temp);

      expect(Directory(p.join(temp.path, 'handover')).existsSync(), isFalse);
      expect(Directory(p.join(temp.path, 'share_plus')).existsSync(), isFalse);
      expect(
        File(p.join(temp.path, 'attachment_1728700000000000')).existsSync(),
        isFalse,
      );
    },
  );

  test('the attachment cache and other files stay', () async {
    final cached = write('attachment_cache/handover/abc/photo.jpg');
    final other = write('attachment_notes');

    await removeLegacyPlaintextCopies(temp);

    expect(cached.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('a folder with nothing to remove is fine', () async {
    await removeLegacyPlaintextCopies(temp);

    expect(temp.listSync(), isEmpty);
  });
}
