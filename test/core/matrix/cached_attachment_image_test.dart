import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/blurhash_image.dart';
import 'package:zuno/core/matrix/cached_attachment_image.dart';

import '../../helpers/fake_attachments.dart';
import '../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;

  setUp(() => server = installAttachmentServer());

  Future<void> pumpImage(
    WidgetTester tester,
    Event event, {
    bool thumbnail = false,
    Widget? progress,
    Widget Function(VoidCallback? retry)? failure,
    BoxFit? fit,
    ImageProvider Function(BuildContext context, ImageProvider attachment)?
    image,
    bool gaplessPlayback = false,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Center(
        child: SizedBox.square(
          dimension: 200,
          child: CachedAttachmentImage(
            event: event,
            thumbnail: thumbnail,
            placeholder: const Text('loading'),
            progress: progress,
            failure: failure,
            fit: fit,
            image: image,
            gaplessPlayback: gaplessPlayback,
          ),
        ),
      ),
    ),
  );

  final picture = find.byWidgetPredicate(
    (widget) => widget is Image && widget.image is! BlurhashImage,
  );

  Future<void> pumpUntilShown(WidgetTester tester) =>
      pumpUntilImageLoads(tester, tester.widget<Image>(picture).image);

  Future<void> pumpUntilDownloaded(WidgetTester tester) => pumpUntil(
    tester,
    () => server.downloads.isNotEmpty,
    reason: 'the download',
  );

  void cache(Event event, {bool thumbnail = false, Uint8List? bytes}) =>
      AttachmentCache.instance.put(
        attachmentCacheKey(event, thumbnail: thumbnail),
        bytes ?? server.served,
      );

  testWidgets('an image not yet here shows the placeholder, then itself', (
    tester,
  ) async {
    server.holdDownloads();
    final event = server.attachment();

    await pumpImage(tester, event);
    await pumpUntilDownloaded(tester);
    expect(find.text('loading'), findsOneWidget);

    server.releaseDownloads();
    await pumpUntilShown(tester);

    expect(find.text('loading'), findsNothing);
    expect(server.downloads, hasLength(1));
  });

  testWidgets('an image already in memory keeps the placeholder until it is '
      'on screen, without downloading', (tester) async {
    final event = server.attachment();
    cache(event);

    await pumpImage(tester, event);
    expect(find.text('loading'), findsOneWidget);

    await pumpUntilShown(tester);

    expect(find.text('loading'), findsNothing);
    expect(server.downloads, isEmpty);
  });

  testWidgets('an image that cannot be downloaded keeps the placeholder, '
      'and a rebuild does not download it again', (tester) async {
    final event = server.attachment();
    server.goneFromServer(event);

    await pumpImage(tester, event);
    await pumpUntilDownloaded(tester);
    await tester.pump();
    await pumpImage(tester, event);
    await tester.pump();

    expect(find.text('loading'), findsOneWidget);
    expect(server.downloads, hasLength(1));
  });

  testWidgets('a failed download loads again once the connection is back', (
    tester,
  ) async {
    final event = server.attachment();
    server.goneFromServer(event);

    await pumpImage(tester, event);
    await pumpUntilDownloaded(tester);
    await tester.pump();

    server.missing.clear();
    retryFailedAttachmentImages();
    await tester.pump();
    await pumpUntilShown(tester);

    expect(server.downloads, hasLength(2));
    expect(find.text('loading'), findsNothing);
  });

  testWidgets('a loaded image is left alone when the connection is back', (
    tester,
  ) async {
    final event = server.attachment();
    cache(event);
    await pumpImage(tester, event);
    await pumpUntilShown(tester);
    final shown = tester.element(picture);

    retryFailedAttachmentImages();
    await tester.pump();

    expect(tester.element(picture), same(shown));
  });

  group('with a blurhash', () {
    Event withBlurhash() => server.attachment(info: photoWithBlurhash);

    testWidgets('it stands in instead of the placeholder', (tester) async {
      server.holdDownloads();

      await pumpImage(tester, withBlurhash());

      expect(blurhashStandIn, findsOneWidget);
      expect(find.text('loading'), findsNothing);

      server.releaseDownloads();
    });

    testWidgets('it takes the fit the picture will have', (tester) async {
      final event = server.attachment(
        eventId: r'$contained',
        info: photoWithBlurhash,
      );
      server.goneFromServer(event);

      await pumpImage(tester, event, fit: BoxFit.contain);

      expect(tester.widget<Image>(blurhashStandIn).fit, BoxFit.contain);
    });

    testWidgets('without a fit it covers its box', (tester) async {
      final event = server.attachment(
        eventId: r'$covered',
        info: photoWithBlurhash,
      );
      server.goneFromServer(event);

      await pumpImage(tester, event);

      expect(tester.widget<Image>(blurhashStandIn).fit, BoxFit.cover);
    });

    testWidgets('it stays until the picture is on screen', (tester) async {
      final event = withBlurhash();
      cache(event);

      await pumpImage(tester, event);
      expect(blurhashStandIn, findsOneWidget);

      await pumpUntilShown(tester);

      expect(blurhashStandIn, findsNothing);
    });

    testWidgets('a download that fails keeps it', (tester) async {
      final event = withBlurhash();
      server.goneFromServer(event);

      await pumpImage(tester, event);
      await pumpUntilDownloaded(tester);
      await tester.pump();

      expect(blurhashStandIn, findsOneWidget);
    });
  });

  group('waited on', () {
    Widget failure(VoidCallback? retry) => retry == null
        ? const Text('cannot show')
        : TextButton(onPressed: retry, child: const Text('failed'));

    testWidgets('progress shows over the stand-in until the picture is on '
        'screen', (tester) async {
      final event = server.attachment();
      cache(event);

      await pumpImage(tester, event, progress: const Text('…'));

      expect(find.text('loading'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);

      await pumpUntilShown(tester);

      expect(find.text('…'), findsNothing);
    });

    testWidgets('a failed download says so, and retrying downloads again', (
      tester,
    ) async {
      final event = server.attachment();
      server.goneFromServer(event);

      await pumpImage(
        tester,
        event,
        progress: const Text('…'),
        failure: failure,
      );
      await pumpUntil(
        tester,
        () => shows('failed'),
        reason: 'the download to fail',
      );

      expect(find.text('…'), findsNothing);
      expect(find.text('loading'), findsNothing);

      server.missing.clear();
      await tester.tap(find.text('failed'));
      await tester.pump();
      expect(find.text('…'), findsOneWidget);
      await pumpUntilShown(tester);

      expect(server.downloads, hasLength(2));
      expect(find.text('…'), findsNothing);
    });

    testWidgets('a picture that cannot be decoded says so, with no retry', (
      tester,
    ) async {
      final event = server.attachment();
      cache(event, bytes: Uint8List(64));

      await pumpImage(
        tester,
        event,
        progress: const Text('…'),
        failure: failure,
      );
      await pumpUntil(
        tester,
        () => shows('cannot show'),
        reason: 'the decode to fail',
      );

      expect(find.text('…'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('swapped for a sharper decode', () {
    ImageProvider small(BuildContext _, ImageProvider attachment) =>
        ResizeImage(attachment, width: 1);

    ImageProvider full(BuildContext _, ImageProvider attachment) => attachment;

    bool picturePainted(WidgetTester tester) =>
        tester.widget<RawImage>(find.byType(RawImage)).image != null;

    testWidgets('with gapless playback the shown picture stays, with no '
        'placeholder or progress, until the sharper one is ready', (
      tester,
    ) async {
      final event = server.attachment();
      cache(event);
      await pumpImage(
        tester,
        event,
        image: small,
        progress: const Text('…'),
        gaplessPlayback: true,
      );
      await pumpUntilShown(tester);

      await pumpImage(
        tester,
        event,
        image: full,
        progress: const Text('…'),
        gaplessPlayback: true,
      );

      expect(tester.widget<Image>(picture).image, isNot(isA<ResizeImage>()));
      expect(find.text('loading'), findsNothing);
      expect(find.text('…'), findsNothing);
      expect(picturePainted(tester), isTrue);

      await pumpUntilShown(tester);

      expect(picturePainted(tester), isTrue);
    });

    testWidgets('without it, the sharper one waits behind the placeholder', (
      tester,
    ) async {
      final event = server.attachment();
      cache(event);
      await pumpImage(tester, event, image: small);
      await pumpUntilShown(tester);

      await pumpImage(tester, event, image: full);

      expect(find.text('loading'), findsOneWidget);
    });

    testWidgets('with gapless playback, another picture still waits behind '
        'the placeholder', (tester) async {
      final first = server.attachment();
      cache(first);
      await pumpImage(tester, first, gaplessPlayback: true);
      await pumpUntilShown(tester);

      await pumpImage(
        tester,
        server.attachment(eventId: r'$other'),
        gaplessPlayback: true,
      );

      expect(find.text('loading'), findsOneWidget);
    });
  });

  group('as a thumbnail', () {
    Event video({String? thumbnailId}) => server.attachment(
      msgtype: MessageTypes.Video,
      body: 'clip.mp4',
      mimetype: 'video/mp4',
      thumbnailId: thumbnailId,
    );

    testWidgets('a video without one shows the stand-in and downloads '
        'nothing, even with bytes cached under its thumbnail', (tester) async {
      final event = video();
      cache(event, thumbnail: true);

      await pumpImage(tester, event, thumbnail: true);
      await tester.pump();

      expect(find.text('loading'), findsOneWidget);
      expect(picture, findsNothing);
      expect(server.downloads, isEmpty);
    });

    testWidgets('a video with one downloads that, not the video', (
      tester,
    ) async {
      await pumpImage(
        tester,
        video(thumbnailId: 'clip-thumb'),
        thumbnail: true,
      );
      await pumpUntilDownloaded(tester);

      expect(server.downloads.single.path, endsWith('/clip-thumb'));
    });

    testWidgets('a photo without one falls back to the photo itself', (
      tester,
    ) async {
      await pumpImage(tester, server.attachment(), thumbnail: true);
      await pumpUntilDownloaded(tester);

      expect(server.downloads.single.path, endsWith('/attachment'));
    });
  });
}
