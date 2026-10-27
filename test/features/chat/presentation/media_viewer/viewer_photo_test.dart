import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_photo.dart';

import '../../../../helpers/fake_attachments.dart';
import '../../../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;
  late int taps;
  late List<bool> zooms;

  setUp(() {
    server = installAttachmentServer();
    taps = 0;
    zooms = [];
  });

  Future<void> pumpPhoto(WidgetTester tester, Event event) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: zunoViewerTheme,
      home: Scaffold(
        body: ViewerPhoto(
          event: event,
          onTap: () => taps++,
          onZoomChanged: zooms.add,
        ),
      ),
    ),
  );

  double scale(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Future<void> doubleTap(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(ViewerPhoto));
    await tester.tapAt(center);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(ZunoDurations.standard);
  }

  testWidgets('shows the full photo, zoomable, filling the screen', (
    tester,
  ) async {
    final event = server.attachment();
    AttachmentCache.instance.put(
      attachmentCacheKey(event, thumbnail: false),
      server.served,
    );

    await pumpPhoto(tester, event);

    final image = find.descendant(
      of: find.byType(InteractiveViewer),
      matching: find.byType(Image),
    );
    expect(image, findsOneWidget);
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(tester.getSize(image), const Size(800, 600));
  });

  testWidgets('while it loads, its blurhash shows under a spinner', (
    tester,
  ) async {
    server.holdDownloads();
    addTearDown(server.releaseDownloads);

    await pumpPhoto(
      tester,
      server.attachment(eventId: r'$loading', info: photoWithBlurhash),
    );

    expect(blurhashStandIn, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a photo that did not load says so, and Try again loads it', (
    tester,
  ) async {
    final event = server.attachment();
    server.goneFromServer(event);

    await pumpPhoto(tester, event);
    await pumpUntil(
      tester,
      () => shows('Photo did not load.'),
      reason: 'the download to fail',
    );

    server.missing.clear();
    await tester.tap(find.text('Try again'));
    await tester.pump(kDoubleTapTimeout);

    expect(find.text('Photo did not load.'), findsNothing);
    await pumpUntil(
      tester,
      () => server.downloads.length == 2,
      reason: 'the second download',
    );
  });

  testWidgets('double-tap zooms in to 2.5x and double-tap again zooms back '
      'out', (tester) async {
    server.holdDownloads();
    addTearDown(server.releaseDownloads);
    await pumpPhoto(tester, server.attachment(eventId: r'$zoom'));

    await doubleTap(tester);
    expect(scale(tester), closeTo(2.5, 0.001));
    expect(zooms, [true]);

    await doubleTap(tester);
    expect(scale(tester), closeTo(1, 0.001));
    expect(zooms, [true, false]);
    expect(taps, 0);
  });

  testWidgets('a single tap reaches onTap after the double-tap window', (
    tester,
  ) async {
    server.holdDownloads();
    addTearDown(server.releaseDownloads);
    await pumpPhoto(tester, server.attachment(eventId: r'$tap'));

    await tester.tap(find.byType(ViewerPhoto));
    await tester.pump(kDoubleTapTimeout);

    expect(taps, 1);
    expect(scale(tester), 1);
  });
}
