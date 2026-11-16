import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/media/attachments/attachment_cache.dart';
import 'package:zuno/core/matrix/media/attachments/blurhash_image.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/media_viewer/media_hero.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_photo.dart';

import '../../../../helpers/fake_attachments.dart';
import '../../../../helpers/pump_until.dart';
import '../../../../helpers/zoom_gestures.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  Future<void> pumpPhoto(WidgetTester tester, Event event) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: zunoViewerTheme,
      home: Scaffold(
        body: ViewerPhoto(event: event, onTap: () {}),
      ),
    ),
  );

  final photoImage = find.descendant(
    of: find.byType(ViewerPhoto),
    matching: find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is! BlurhashImage,
    ),
  );

  ImageProvider shownImage(WidgetTester tester) =>
      tester.widget<Image>(photoImage).image;

  void cacheFull(Event event) => AttachmentCache.instance.put(
    attachmentCacheKey(event, thumbnail: false),
    server.served,
  );

  Future<void> doubleTap(WidgetTester tester) =>
      doubleTapAt(tester, tester.getCenter(find.byType(ViewerPhoto)));

  testWidgets('shows the photo, zoomable, filling the screen', (tester) async {
    final event = server.attachment();
    cacheFull(event);

    await pumpPhoto(tester, event);

    expect(photoImage, findsOneWidget);
    expect(tester.widget<Image>(photoImage).fit, BoxFit.contain);
    expect(tester.getSize(photoImage), const Size(800, 600));
  });

  testWidgets('decodes the photo no larger than the screen until zoomed', (
    tester,
  ) async {
    final event = server.attachment();
    cacheFull(event);

    await pumpPhoto(tester, event);

    final decoded = shownImage(tester) as ResizeImage;
    final screen = tester.view.physicalSize;
    expect(
      (decoded.width, decoded.height, decoded.policy),
      (screen.width.round(), screen.height.round(), ResizeImagePolicy.fit),
    );
  });

  testWidgets('zooming in swaps to the full photo, keeping the shown one '
      'with no blurhash or spinner until it is ready', (tester) async {
    final event = server.attachment(
      eventId: r'$sharp',
      info: photoWithBlurhash,
    );
    cacheFull(event);
    await pumpPhoto(tester, event);
    await pumpUntilImageLoads(tester, shownImage(tester));

    await doubleTap(tester);

    expect(shownImage(tester), isNot(isA<ResizeImage>()));
    expect(blurhashStandIn, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final painted = find.descendant(
      of: find.byType(ViewerPhoto),
      matching: find.byType(RawImage),
    );
    expect(tester.widget<RawImage>(painted).image, isNotNull);

    await pumpUntilImageLoads(tester, shownImage(tester));

    expect(blurhashStandIn, findsNothing);
    expect(tester.widget<RawImage>(painted).image, isNotNull);
  });

  testWidgets('zooming back out keeps the full photo', (tester) async {
    final event = server.attachment(eventId: r'$kept');
    cacheFull(event);
    await pumpPhoto(tester, event);

    await doubleTap(tester);
    await doubleTap(tester);

    expect(zoomOf(tester, find.byType(ViewerFrame)), closeTo(1, 0.001));
    expect(shownImage(tester), isNot(isA<ResizeImage>()));
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
}
