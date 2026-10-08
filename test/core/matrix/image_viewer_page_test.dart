import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/image_viewer_page.dart';

import '../../helpers/fake_attachments.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  testWidgets('shows the full image, zoomable, with share and save', (
    tester,
  ) async {
    final event = server.attachment();
    AttachmentCache.instance.put(
      attachmentCacheKey(event, thumbnail: false),
      server.served,
    );

    await tester.pumpWidget(MaterialApp(home: ImageViewerPage(event: event)));

    expect(
      find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
  });

  testWidgets('keeps the spinner while the image cannot be fetched', (
    tester,
  ) async {
    final event = server.attachment();
    server.goneFromServer(event);

    await tester.pumpWidget(MaterialApp(home: ImageViewerPage(event: event)));
    await pumpWhileFetching(
      tester,
      rounds: 500,
      until: () => server.downloads.isNotEmpty,
    );

    expect(server.downloads, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
