import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/image_viewer_page.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  Future<void> pumpViewer(WidgetTester tester, Event event) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageViewerPage(event: event),
        ),
      );

  testWidgets('shows the full image, zoomable, with share and save', (
    tester,
  ) async {
    final event = server.attachment();
    AttachmentCache.instance.put(
      attachmentCacheKey(event, thumbnail: false),
      server.served,
    );

    await pumpViewer(tester, event);

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

  testWidgets('while it loads, its blurhash shows under a spinner', (
    tester,
  ) async {
    server.holdDownloads();

    await pumpViewer(tester, server.attachment(info: photoWithBlurhash));

    expect(blurhashStandIn, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    server.releaseDownloads();
  });

  testWidgets('a photo that did not load says so, and Retry loads it', (
    tester,
  ) async {
    final event = server.attachment();
    server.goneFromServer(event);

    await pumpViewer(tester, event);
    await pumpUntil(
      tester,
      () => shows('Photo did not load.'),
      reason: 'the download to fail',
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);

    server.missing.clear();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('Photo did not load.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await pumpUntil(
      tester,
      () => server.downloads.length == 2,
      reason: 'the second download',
    );
  });
}
