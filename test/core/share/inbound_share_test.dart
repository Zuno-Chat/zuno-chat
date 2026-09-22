import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/share/inbound_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('InboundShare.fromChannel', () {
    test('parses text and files', () {
      final share = InboundShare.fromChannel({
        'text': 'https://example.org',
        'files': [
          {'uri': 'content://a/1', 'name': 'a.jpg', 'mimeType': 'image/jpeg'},
          {'uri': 'content://a/2', 'name': 'b.bin', 'mimeType': ''},
        ],
      });
      expect(share!.text, 'https://example.org');
      expect(share.files.map((f) => f.name), ['a.jpg', 'b.bin']);
      expect(share.files.first.mimeType, 'image/jpeg');
      expect(share.files.last.mimeType, isNull);
    });

    test('text only and files only both parse', () {
      expect(InboundShare.fromChannel({'text': 'hi'})!.files, isEmpty);
      final files = InboundShare.fromChannel({
        'files': [
          {'uri': 'content://a/1', 'name': 'a.pdf'},
        ],
      });
      expect(files!.text, isNull);
      expect(files.files.single.uri, 'content://a/1');
    });

    test('blank text, malformed items and non-maps yield nothing', () {
      expect(InboundShare.fromChannel({'text': '   ', 'files': []}), isNull);
      expect(InboundShare.fromChannel('nope'), isNull);
      expect(InboundShare.fromChannel(null), isNull);
      expect(
        InboundShare.fromChannel({
          'files': [
            {'uri': 'content://a/1'},
            'junk',
          ],
        }),
        isNull,
      );
    });
  });

  group('partitionSharedFiles', () {
    test('splits by mime, with a video-extension fallback', () {
      final result = partitionSharedFiles([
        XFile('/c/a.jpg', mimeType: 'image/jpeg'),
        XFile('/c/b.mp4', mimeType: 'video/mp4'),
        XFile('/c/c.pdf', mimeType: 'application/pdf'),
        XFile('/c/d.mov'),
        XFile('/c/e.txt'),
        XFile('/c/f.jpg', mimeType: 'application/octet-stream'),
      ]);
      expect(result.media.map((f) => f.path), [
        '/c/a.jpg',
        '/c/b.mp4',
        '/c/d.mov',
      ]);
      expect(result.others.map((f) => f.path), [
        '/c/c.pdf',
        '/c/e.txt',
        '/c/f.jpg',
      ]);
    });
  });

  group('channel', () {
    test('an incoming share call reaches the stream', () async {
      initInboundShareChannel();
      final received = onInboundShare.first;
      await messenger.handlePlatformMessage(
        'zuno/share',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('share', {'text': 'hello'}),
        ),
        (_) {},
      );
      expect((await received).text, 'hello');
    });

    test('takeLaunchShare parses the native reply', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takeLaunchShare');
        return {'text': 'cold'};
      });
      expect((await takeLaunchShare())!.text, 'cold');
    });

    test(
      'copySharedFilesToCache zips paths with names and mimes, skipping nulls',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'copyToCache');
          expect(call.arguments['uris'], ['content://a/1', 'content://a/2']);
          expect(call.arguments['names'], ['a.jpg', 'b.pdf']);
          return ['/cache/shared/x/0/a.jpg', null];
        });
        final copies = await copySharedFilesToCache(const [
          SharedFile(
            uri: 'content://a/1',
            name: 'a.jpg',
            mimeType: 'image/jpeg',
          ),
          SharedFile(uri: 'content://a/2', name: 'b.pdf'),
        ]);
        expect(copies.single.path, '/cache/shared/x/0/a.jpg');
        expect(copies.single.name, 'a.jpg');
        expect(copies.single.mimeType, 'image/jpeg');
      },
    );

    test('copySharedFilesToCache with no files never calls native', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => fail('called'));
      expect(await copySharedFilesToCache(const []), isEmpty);
    });
  });

  test('discardSharedCopies deletes files and ignores missing ones', () async {
    final dir = await Directory.systemTemp.createTemp('zuno_share_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.txt')..writeAsStringSync('x');
    await discardSharedCopies([XFile(file.path), XFile('${dir.path}/gone')]);
    expect(file.existsSync(), isFalse);
  });
}
