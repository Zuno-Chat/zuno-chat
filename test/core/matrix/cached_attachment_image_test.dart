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
}
