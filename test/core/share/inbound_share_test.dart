import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/share/inbound_share.dart';

import '../../helpers/platform_capabilities.dart';

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
    Future<void> receiveShare(String text) => messenger.handlePlatformMessage(
      'zuno/share',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('share', {'text': text}),
      ),
      (_) {},
    );

    Future<List<String?>> listenBriefly() async {
      final heard = <String?>[];
      final sub = onInboundShare.listen((share) => heard.add(share.text));
      await pumpEventQueue();
      await sub.cancel();
      return heard;
    }

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

    test('a share that arrives before anyone listens reaches the first '
        'listener, once', () async {
      initInboundShareChannel();
      await receiveShare('early');

      final first = <String?>[];
      final second = <String?>[];
      final firstSub = onInboundShare.listen((s) => first.add(s.text));
      final secondSub = onInboundShare.listen((s) => second.add(s.text));
      await pumpEventQueue();
      await firstSub.cancel();
      await secondSub.cancel();

      expect(first, ['early']);
      expect(second, isEmpty);
      expect(await listenBriefly(), isEmpty);
    });

    test('of several unheard shares, only the latest is kept', () async {
      initInboundShareChannel();
      await receiveShare('older');
      await receiveShare('newer');

      expect(await listenBriefly(), ['newer']);
      expect(await listenBriefly(), isEmpty);
    });

    test('a share heard on arrival is not kept for a later listener', () async {
      initInboundShareChannel();
      final heard = <String?>[];
      final sub = onInboundShare.listen((share) => heard.add(share.text));
      await receiveShare('now');
      await pumpEventQueue();
      await sub.cancel();

      expect(heard, ['now']);
      expect(await listenBriefly(), isEmpty);
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

    test(
      'copySharedFilesToCache returns no copies when the copy fails',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'bad_arguments'),
        );

        final copies = await copySharedFilesToCache(const [
          SharedFile(uri: 'content://a/1', name: 'a.jpg'),
        ]);

        expect(copies, isEmpty);
      },
    );

    test('copySharedFilesToCache returns no copies when nothing answers on '
        'the native side', () async {
      final copies = await copySharedFilesToCache(const [
        SharedFile(uri: 'content://a/1', name: 'a.jpg'),
      ]);

      expect(copies, isEmpty);
    });
  });

  test('iOS takes its launch share and copies shared files over the '
      'channel', () async {
    final ios = capabilitiesFor(AppPlatform.ios);
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'takeLaunchShare' => {
          'files': [
            {
              'uri': 'file:///Caches/Share/Imports/a/0/IMG_0001.HEIC',
              'name': 'IMG_0001.HEIC',
              'mimeType': 'image/heic',
            },
          ],
        },
        'copyToCache' => ['/Caches/Share/Copies/b/0/IMG_0001.HEIC'],
        _ => null,
      };
    });

    final share = await takeLaunchShare(capabilities: ios);
    final copies = await copySharedFilesToCache(
      share!.files,
      capabilities: ios,
    );

    expect(copies.single.path, '/Caches/Share/Copies/b/0/IMG_0001.HEIC');
    expect(copies.single.mimeType, 'image/heic');
    expect(calls.map((call) => call.method), [
      'takeLaunchShare',
      'copyToCache',
    ]);
    expect(calls.last.arguments, {
      'uris': ['file:///Caches/Share/Imports/a/0/IMG_0001.HEIC'],
      'names': ['IMG_0001.HEIC'],
    });
  });

  group('on a platform without inbound share', () {
    final ios = capabilitiesLike(iosCapabilities, inboundShare: false);
    late List<String> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {'text': 'cold'};
      });
    });

    test('there is never a launch share', () async {
      expect(await takeLaunchShare(capabilities: ios), isNull);
      expect(calls, isEmpty);
    });

    test('shared files are never copied', () async {
      final copies = await copySharedFilesToCache(const [
        SharedFile(uri: 'content://a/1', name: 'a.jpg'),
      ], capabilities: ios);

      expect(copies, isEmpty);
      expect(calls, isEmpty);
    });

    test('no handler is registered for incoming shares', () async {
      channel.setMethodCallHandler(null);
      initInboundShareChannel(capabilities: ios);

      ByteData? reply;
      var replied = false;
      await messenger.handlePlatformMessage(
        'zuno/share',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('share', {'text': 'hello'}),
        ),
        (data) {
          replied = true;
          reply = data;
        },
      );

      expect(replied, isTrue);
      expect(reply, isNull);
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
