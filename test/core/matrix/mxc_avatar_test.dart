import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/mxc_avatar.dart';
import 'package:zuno/core/matrix/mxc_avatar_image.dart';
import 'package:zuno/core/ui/zuno_colors.dart';

import '../../helpers/fake_matrix.dart';

class _MediaCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> object,
  ) async {}

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;
}

void main() {
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));
  final mxc = Uri.parse('mxc://example.org/abc');

  late List<http.Request> mediaRequests;
  late http.Response Function() mediaResponse;
  late Client client;
  late Directory dir;
  late DiskAttachmentCache disk;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PaintingBinding.instance.imageCache.clear();
    mediaRequests = [];
    mediaResponse = () => http.Response.bytes(png, 200);
    client = buildTestClient(
      userId: '@me:example.org',
      database: _MediaCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.url.pathSegments.last == 'versions') {
          return http.Response(
            jsonEncode({
              'versions': ['v1.11'],
            }),
            200,
          );
        }
        mediaRequests.add(request);
        return mediaResponse();
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    dir = Directory.systemTemp.createTempSync('zuno_avatar');
    disk = DiskAttachmentCache.forTest(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  MxcAvatarImage provider(AvatarBucket bucket) =>
      MxcAvatarImage(client: client, mxc: mxc, bucket: bucket, disk: disk);

  Uri uniqueMxc() =>
      Uri.parse('mxc://example.org/${DateTime.now().microsecondsSinceEpoch}');

  Future<ImageInfo> resolve(ImageProvider image) {
    final completer = Completer<ImageInfo>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info);
      },
      onError: (error, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> settle(WidgetTester tester, Widget widget) =>
      tester.runAsync(() async {
        await tester.pumpWidget(widget);
        for (var i = 0; i < 100 && mediaRequests.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

  Widget host(Uri? avatarUrl) => MaterialApp(
    home: Scaffold(
      body: MxcAvatar(
        client: client,
        avatarUrl: avatarUrl,
        fallbackText: 'maya',
      ),
    ),
  );

  test('the bucket follows the diameter', () {
    expect(AvatarBucket.forDiameter(32), AvatarBucket.small);
    expect(AvatarBucket.forDiameter(56), AvatarBucket.small);
    expect(AvatarBucket.forDiameter(56.5), AvatarBucket.large);
    expect(AvatarBucket.forDiameter(112), AvatarBucket.large);
  });

  test('providers are equal on address and bucket', () {
    expect(provider(AvatarBucket.small), provider(AvatarBucket.small));
    expect(
      provider(AvatarBucket.small).hashCode,
      provider(AvatarBucket.small).hashCode,
    );
    expect(provider(AvatarBucket.small), isNot(provider(AvatarBucket.large)));
  });

  testWidgets('two equal providers cost one request, at the small size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final info = await resolve(provider(AvatarBucket.small));
      await resolve(provider(AvatarBucket.small));

      expect(info.image.width, 1);
      expect(mediaRequests, hasLength(1));
      final query = mediaRequests.single.url.queryParameters;
      expect(query['width'], '96');
      expect(query['height'], '96');
      expect(query['method'], 'crop');
      expect(
        mediaRequests.single.headers['authorization'],
        'Bearer test-token',
      );
    });
  });

  testWidgets('the large bucket asks for a 320 scaled thumbnail', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await resolve(provider(AvatarBucket.large));

      final query = mediaRequests.single.url.queryParameters;
      expect(query['width'], '320');
      expect(query['method'], 'scale');
    });
  });

  testWidgets('a fresh image cache reads the avatar from disk', (tester) async {
    await tester.runAsync(() async {
      await resolve(provider(AvatarBucket.small));
      PaintingBinding.instance.imageCache.clear();
      await resolve(provider(AvatarBucket.small));

      expect(mediaRequests, hasLength(1));
    });
  });

  testWidgets('a 404 is an error, and the next try asks again', (tester) async {
    await tester.runAsync(() async {
      mediaResponse = () => http.Response('', 404);
      await expectLater(
        resolve(provider(AvatarBucket.small)),
        throwsA(anything),
      );
      await Future<void>.delayed(Duration.zero);

      mediaResponse = () => http.Response.bytes(png, 200);
      await resolve(provider(AvatarBucket.small));

      expect(mediaRequests, hasLength(2));
    });
  });

  testWidgets('bytes that do not decode are dropped from disk', (tester) async {
    await tester.runAsync(() async {
      mediaResponse = () => http.Response.bytes([1, 2, 3], 200);
      await expectLater(
        resolve(provider(AvatarBucket.small)),
        throwsA(anything),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await disk.get('avatar:$mxc:small', expires: false), isNull);
    });
  });

  testWidgets('no address shows the ink initial on a tone, and asks nothing', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));

    expect(find.text('M'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, avatarToneFor('maya'));
    expect(avatar.foregroundColor, zunoInk);
    expect(avatar.foregroundImage, isNull);
    expect(mediaRequests, isEmpty);
  });

  testWidgets('the initial scales with the avatar', (tester) async {
    Future<double?> initialSize(double radius) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MxcAvatar(
            client: client,
            avatarUrl: null,
            fallbackText: 'maya',
            radius: radius,
          ),
        ),
      );
      return tester.widget<Text>(find.text('M')).style?.fontSize;
    }

    expect(await initialSize(26), closeTo(19.76, 0.01));
    expect(await initialSize(16), closeTo(12.16, 0.01));
    expect(await initialSize(56), closeTo(42.56, 0.01));
  });

  testWidgets('a tone seed picks the tone instead of the name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MxcAvatar(
          client: client,
          avatarUrl: null,
          fallbackText: 'maya',
          toneSeed: '@maya:zuno.chat',
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, avatarToneFor('@maya:zuno.chat'));
    expect(avatar.backgroundColor, isNot(avatarToneFor('maya')));
  });

  testWidgets('a failed fetch keeps the initial and throws nothing', (
    tester,
  ) async {
    mediaResponse = () => http.Response('', 404);
    await settle(tester, host(uniqueMxc()));
    await tester.pump();

    expect(find.text('M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bytes that do not decode keep the initial and throw nothing', (
    tester,
  ) async {
    mediaResponse = () => http.Response.bytes([1, 2, 3], 200);
    await settle(tester, host(uniqueMxc()));
    await tester.pump();

    expect(find.text('M'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(mediaRequests, hasLength(1));
  });

  testWidgets('a rebuild does not ask again', (tester) async {
    final address = uniqueMxc();
    await settle(tester, host(address));
    await tester.pump();
    await tester.pumpWidget(host(address));
    await tester.pump();

    expect(mediaRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank text falls back to a question mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MxcAvatar(client: client, avatarUrl: null, fallbackText: '  '),
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('a failing avatar asks once, however often it repaints', (
    tester,
  ) async {
    mediaResponse = () => http.Response('', 404);
    final address = uniqueMxc();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                MxcAvatar(
                  client: client,
                  avatarUrl: address,
                  fallbackText: 'maya',
                ),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
      for (var i = 0; i < 100 && mediaRequests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(mediaRequests, hasLength(1));
    expect(find.text('M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('once the picture is there, the initial is gone', (tester) async {
    final address = uniqueMxc();
    await settle(tester, host(address));
    await tester.pump();

    expect(find.text('M'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
