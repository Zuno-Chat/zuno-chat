import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:zuno/core/matrix/playable_media_file.dart';

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
    String fallbackExtension = '.mp4',
  }) => playableMediaFile(
    cached,
    mimetype: mimetype,
    fileName: fileName,
    fallbackExtension: fallbackExtension,
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

  test('the extension follows the audio type of a voice message', () async {
    expect(p.extension((await playable(mimetype: 'audio/ogg')).path), '.ogg');
    expect(p.extension((await playable(mimetype: 'audio/mp4')).path), '.m4a');
    expect(p.extension((await playable(mimetype: 'audio/mpeg')).path), '.mp3');
  });

  test('an unknown type falls back to the file name, then to the caller\'s '
      'default', () async {
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
      p.extension(
        (await playable(
          mimetype: null,
          fileName: 'voice',
          fallbackExtension: '.ogg',
        )).path,
      ),
      '.ogg',
    );
  });

  test('opening the same file again reuses its link', () async {
    await playable();

    final file = await playable();

    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(links.listSync(), hasLength(1));
  });
}
