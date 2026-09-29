import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:zuno/core/matrix/playable_video_file.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  late Directory root;
  late Directory links;
  late File cached;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuno_playable');
    links = Directory(p.join(root.path, 'links'))..createSync();
    cached = File(p.join(root.path, '3f2a9c'))..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<File> playable({
    bool ios = true,
    String? mimetype = 'video/mp4',
    String? fileName,
  }) => playableVideoFile(
    cached,
    mimetype: mimetype,
    fileName: fileName,
    capabilities: ios ? iosCapabilities : androidCapabilities,
    linkDirectory: links,
  );

  test(
    'where the player reads the content, the cached file plays as is',
    () async {
      final file = await playable(ios: false);

      expect(file.path, cached.path);
      expect(links.listSync(), isEmpty);
    },
  );

  test('where the player needs an extension, it plays through a named link '
      'to the same file', () async {
    final file = await playable();

    expect(p.extension(file.path), '.mp4');
    expect(await FileSystemEntity.isLink(file.path), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('the extension follows the video type', () async {
    expect(
      p.extension((await playable(mimetype: 'video/quicktime')).path),
      '.mov',
    );
  });

  test('an unknown type falls back to the file name, then to mp4', () async {
    expect(
      p.extension(
        (await playable(
          mimetype: 'video/x-unknown',
          fileName: 'clip.m4v',
        )).path,
      ),
      '.m4v',
    );
    expect(
      p.extension((await playable(mimetype: null, fileName: 'clip')).path),
      '.mp4',
    );
  });

  test('opening the same video again reuses its link', () async {
    await playable();

    final file = await playable();

    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(links.listSync(), hasLength(1));
  });
}
