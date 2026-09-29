import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/cached_attachment_image.dart';

import '../../helpers/fake_attachments.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  Future<void> pumpImage(WidgetTester tester, Event event) => tester.pumpWidget(
    MaterialApp(
      home: CachedAttachmentImage(
        event: event,
        thumbnail: false,
        placeholder: const Text('loading'),
        builder: (context, bytes) => Text('${bytes.length} bytes'),
      ),
    ),
  );

  testWidgets('an image already in memory shows at once', (tester) async {
    final event = server.attachment();
    AttachmentCache.instance.put(
      attachmentCacheKey(event, thumbnail: false),
      server.served,
    );

    await pumpImage(tester, event);

    expect(find.text('${server.served.length} bytes'), findsOneWidget);
    expect(server.downloads, isEmpty);
  });

  testWidgets('an image not yet here shows the placeholder, then itself', (
    tester,
  ) async {
    final event = server.attachment();

    await pumpImage(tester, event);
    expect(find.text('loading'), findsOneWidget);

    await pumpWhileFetching(tester);
    await tester.pump();

    expect(find.text('${server.served.length} bytes'), findsOneWidget);
    expect(server.downloads, hasLength(1));
  });

  testWidgets('an image that cannot be downloaded keeps the placeholder', (
    tester,
  ) async {
    final event = server.attachment();
    server.goneFromServer(event);

    await pumpImage(tester, event);
    await pumpWhileFetching(tester);
    await tester.pump();

    expect(find.text('loading'), findsOneWidget);
  });

  group('as a thumbnail', () {
    Future<void> pumpThumbnail(WidgetTester tester, Event event) =>
        tester.pumpWidget(
          MaterialApp(
            home: CachedAttachmentImage(
              event: event,
              thumbnail: true,
              placeholder: const Text('loading'),
              noThumbnail: const Text('no thumbnail'),
              builder: (context, bytes) => Text('${bytes.length} bytes'),
            ),
          ),
        );

    Event video({String? thumbnailId}) => server.attachment(
      msgtype: MessageTypes.Video,
      body: 'clip.mp4',
      mimetype: 'video/mp4',
      thumbnailId: thumbnailId,
    );

    testWidgets('a video without one shows the stand-in and downloads '
        'nothing', (tester) async {
      await pumpThumbnail(tester, video());
      await pumpWhileFetching(tester);
      await tester.pump();

      expect(find.text('no thumbnail'), findsOneWidget);
      expect(server.downloads, isEmpty);
    });

    testWidgets('a video without one ignores bytes cached under its '
        'thumbnail', (tester) async {
      final event = video();
      AttachmentCache.instance.put(
        attachmentCacheKey(event, thumbnail: true),
        server.served,
      );

      await pumpThumbnail(tester, event);

      expect(find.text('no thumbnail'), findsOneWidget);
    });

    testWidgets('a video with one downloads that, not the video', (
      tester,
    ) async {
      await pumpThumbnail(tester, video(thumbnailId: 'clip-thumb'));
      await pumpWhileFetching(tester);
      await tester.pump();

      expect(find.text('${server.served.length} bytes'), findsOneWidget);
      expect(server.downloads.single.path, endsWith('/clip-thumb'));
    });

    testWidgets('a photo without one falls back to the photo itself', (
      tester,
    ) async {
      await pumpThumbnail(tester, server.attachment());
      await pumpWhileFetching(tester);
      await tester.pump();

      expect(find.text('${server.served.length} bytes'), findsOneWidget);
      expect(server.downloads.single.path, endsWith('/attachment'));
    });
  });
}
