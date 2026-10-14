import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/gallery_viewer_page.dart';
import 'package:zuno/core/matrix/image_viewer_page.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/send_progress.dart';
import 'package:zuno/core/matrix/video_viewer_page.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/data/composed_image.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/message_contents/pending_attachment_tile.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_matrix.dart';

const _meta = Text('09:41');

class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) routes.add(route);
  }

  Widget page(BuildContext context) =>
      (routes.single as MaterialPageRoute<dynamic>).builder(context);
}

void main() {
  late AttachmentServer server;
  late _Pushes pushes;

  setUp(() {
    server = installAttachmentServer();
    pushes = _Pushes();
  });

  Event media(
    String id, {
    String msgtype = MessageTypes.Image,
    Map<String, Object?> info = const {'w': 400, 'h': 300},
    Map<String, Object?> extra = const {},
  }) => buildTestEvent(
    server.room,
    eventId: '\$$id',
    senderId: '@bob:example.org',
    status: EventStatus.synced,
    content: {
      'msgtype': msgtype,
      'body': '$id.jpg',
      'url': 'mxc://example.org/$id',
      'info': info,
      ...extra,
    },
  );

  Event galleryItem(
    String id,
    int index,
    int count, {
    String msgtype = MessageTypes.Image,
  }) => media(
    id,
    msgtype: msgtype,
    info: {'w': 400, 'h': 300, 'thumbnail_url': 'mxc://example.org/$id-thumb'},
    extra: galleryGroupContent(id: 'g', index: index, count: count),
  );

  void thumbnailOnPhone(Event event) => AttachmentCache.instance.put(
    attachmentCacheKey(event, thumbnail: true),
    onePixelPng,
  );

  PendingAttachmentSend sending(
    Event event, {
    bool preview = true,
    int? width,
    int? height,
  }) => PendingAttachmentSend(
    eventId: event.eventId,
    previewBytes: preview ? onePixelPng : null,
    width: width,
    height: height,
    kind: SendMediaKind.video,
    stage: SendStage.uploading,
    stageProgress: 0.5,
  );

  Future<BuildContext> pumpIn(WidgetTester tester, Widget child) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: zunoLightTheme,
        navigatorObservers: [pushes],
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return Center(child: SizedBox(width: 240, child: child));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return context;
  }

  double screenWidth(WidgetTester tester) =>
      tester.view.physicalSize.width / tester.view.devicePixelRatio;

  double? shownAt(WidgetTester tester, Finder within) => tester
      .widget<MediaImage>(
        find.descendant(of: within, matching: find.byType(MediaImage)),
      )
      .shownAt;

  group('MediaImage', () {
    Uint8List photo(int width, int height) =>
        img.encodePng(img.Image(width: width, height: height));

    Future<(int, int)> decode(
      WidgetTester tester,
      Uint8List bytes, {
      double? shownAt,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Center(
            child: SizedBox.square(
              dimension: 120,
              child: MediaImage.memory(bytes, shownAt: shownAt),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100; i++) {
        final image = tester.widget<RawImage>(find.byType(RawImage)).image;
        if (image != null) return (image.width, image.height);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      fail('the image never decoded');
    }

    testWidgets('a wide photo is decoded tall enough to cover its box', (
      tester,
    ) async {
      expect(await decode(tester, photo(1600, 1200), shownAt: 120), (480, 360));
    });

    testWidgets('a tall photo is decoded wide enough to cover its box', (
      tester,
    ) async {
      expect(await decode(tester, photo(1200, 1600), shownAt: 120), (360, 480));
    });

    testWidgets('a panorama is decoded no longer than twice its box', (
      tester,
    ) async {
      expect(await decode(tester, photo(4000, 400), shownAt: 120), (720, 72));
      expect(await decode(tester, photo(400, 4000), shownAt: 120), (72, 720));
    });

    testWidgets('a photo smaller than its box is never enlarged', (
      tester,
    ) async {
      expect(await decode(tester, photo(64, 48), shownAt: 120), (64, 48));
    });

    testWidgets('without a size it covers the width of the screen', (
      tester,
    ) async {
      expect(await decode(tester, photo(1600, 1200)), (1440, 1080));
    });

    testWidgets('a photo that cannot be decoded raises no error', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox.square(
            dimension: 120,
            child: MediaImage.memory(Uint8List(64), shownAt: 120),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  group('mediaAspectRatio', () {
    test('is unknown without sensible dimensions', () {
      expect(mediaAspectRatio(null, 300), isNull);
      expect(mediaAspectRatio(400, null), isNull);
      expect(mediaAspectRatio(0, 300), isNull);
      expect(mediaAspectRatio(400, -1), isNull);
    });

    test('keeps ordinary photos and videos as they are', () {
      expect(mediaAspectRatio(400, 300), 4 / 3);
      expect(mediaAspectRatio(1080, 1920), 9 / 16);
      expect(mediaAspectRatio(1920, 1080), 16 / 9);
    });

    test('a long screenshot is cropped to a phone-tall bubble', () {
      expect(mediaAspectRatio(1080, 6000), 9 / 16);
    });

    test('a panorama is cropped to a widescreen bubble', () {
      expect(mediaAspectRatio(8000, 1000), 16 / 9);
    });
  });

  group('ImageMessage', () {
    testWidgets('shows the thumbnail in its own shape with the time on it', (
      tester,
    ) async {
      final event = media('photo');
      thumbnailOnPhone(event);

      await pumpIn(
        tester,
        ImageMessage(event: event, mediaMeta: _meta, showTimeOverlay: true),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        4 / 3,
      );
      expect(find.text('09:41'), findsOneWidget);
    });

    testWidgets('a photo is decoded to cover the width of the screen', (
      tester,
    ) async {
      final event = media('photo');
      thumbnailOnPhone(event);

      await pumpIn(
        tester,
        ImageMessage(event: event, mediaMeta: _meta, showTimeOverlay: true),
      );

      expect(shownAt(tester, find.byType(ImageMessage)), isNull);
    });

    testWidgets('a captioned photo leaves the time to the caption', (
      tester,
    ) async {
      await pumpIn(
        tester,
        ImageMessage(
          event: media('photo'),
          mediaMeta: _meta,
          showTimeOverlay: false,
        ),
      );

      expect(find.text('09:41'), findsNothing);
    });

    testWidgets('a photo of unknown size is kept short, spinning until '
        'it loads', (tester) async {
      await pumpIn(
        tester,
        ImageMessage(
          event: media('photo', info: const {}),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );

      expect(find.byType(AspectRatio), findsNothing);
      expect(
        tester
            .widget<ConstrainedBox>(
              find
                  .ancestor(
                    of: find.byType(Stack).first,
                    matching: find.byType(ConstrainedBox),
                  )
                  .first,
            )
            .constraints
            .maxHeight,
        200,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('tapping it opens the photo full screen', (tester) async {
      final event = media('photo');
      final context = await pumpIn(
        tester,
        ImageMessage(event: event, mediaMeta: _meta, showTimeOverlay: true),
      );

      await tester.tap(find.byType(AspectRatio));

      final page = pushes.page(context);
      expect(page, isA<ImageViewerPage>());
      expect((page as ImageViewerPage).event, same(event));
    });

    testWidgets('while sending it shows the local preview and progress, '
        'and cannot be opened', (tester) async {
      final event = media('photo');
      await pumpIn(
        tester,
        ImageMessage(
          event: event,
          pendingSend: sending(event),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );

      await tester.tap(find.byType(AspectRatio));

      expect(find.byType(Image), findsOneWidget);
      expect(shownAt(tester, find.byType(ImageMessage)), isNull);
      expect(find.byType(AttachmentProgressBar), findsOneWidget);
      expect(pushes.routes, isEmpty);
    });
  });

  group('VideoMessage', () {
    Event video({Map<String, Object?>? info}) => media(
      'clip',
      msgtype: MessageTypes.Video,
      info:
          info ??
          const {
            'w': 1920,
            'h': 1080,
            'duration': 42000,
            'thumbnail_url': 'mxc://example.org/clip-thumb',
          },
    );

    testWidgets('shows a play button and how long it runs', (tester) async {
      final event = video();
      thumbnailOnPhone(event);

      await pumpIn(
        tester,
        VideoMessage(event: event, mediaMeta: _meta, showTimeOverlay: true),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);
      expect(find.text('09:41'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a video sent without a thumbnail shows the play button '
        'over an empty frame, without downloading the video', (tester) async {
      await pumpIn(
        tester,
        VideoMessage(
          event: video(info: const {'w': 1920, 'h': 1080}),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(AspectRatioPlaceholder), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(server.downloads, isEmpty);
    });

    testWidgets('a video without a length shows none', (tester) async {
      await pumpIn(
        tester,
        VideoMessage(
          event: video(info: const {'w': 1920, 'h': 1080}),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );

      expect(find.textContaining(':'), findsOneWidget);
    });

    testWidgets('a captioned video shows neither length nor time on it', (
      tester,
    ) async {
      await pumpIn(
        tester,
        VideoMessage(event: video(), mediaMeta: _meta, showTimeOverlay: false),
      );

      expect(find.text('0:42'), findsNothing);
      expect(find.text('09:41'), findsNothing);
    });

    testWidgets('tapping it opens the video player', (tester) async {
      final event = video();
      final context = await pumpIn(
        tester,
        VideoMessage(event: event, mediaMeta: _meta, showTimeOverlay: true),
      );

      await tester.tap(find.byType(AspectRatio));

      final page = pushes.page(context);
      expect(page, isA<VideoViewerPage>());
      expect((page as VideoViewerPage).event, same(event));
    });

    testWidgets('while sending it shows the local preview, no play button, '
        'and cannot be opened', (tester) async {
      final event = video();
      await pumpIn(
        tester,
        VideoMessage(
          event: event,
          pendingSend: sending(event, width: 1080, height: 1920),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );

      await tester.tap(find.byType(AspectRatio));

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.text('0:42'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        9 / 16,
      );
      expect(pushes.routes, isEmpty);
    });

    testWidgets('while sending without a preview it holds the shape empty', (
      tester,
    ) async {
      final event = video();
      await pumpIn(
        tester,
        VideoMessage(
          event: event,
          pendingSend: sending(
            event,
            preview: false,
            width: 1920,
            height: 1080,
          ),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );

      expect(find.byType(AspectRatioPlaceholder), findsOneWidget);
    });

    testWidgets('while sending without a preview or shape it waits for the '
        'thumbnail', (tester) async {
      final event = video();
      await pumpIn(
        tester,
        VideoMessage(
          event: event,
          pendingSend: sending(event, preview: false),
          mediaMeta: _meta,
          showTimeOverlay: true,
        ),
      );

      expect(find.byType(AspectRatioPlaceholder), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('GalleryMessage', () {
    final retried = <FailedMediaSend>[];

    setUp(retried.clear);

    Widget gallery(
      List<Event> events, {
      List<FailedMediaSend> failed = const [],
      PendingAttachmentSend? pending,
    }) => GalleryMessage(
      events: events,
      failed: failed,
      onRetry: retried.add,
      pendingSend: pending,
      mediaMeta: _meta,
    );

    List<Event> items(int count) => [
      for (var i = 0; i < count; i++) galleryItem('g$i', i, count),
    ];

    testWidgets('side by side items decode at half the screen, an odd one '
        'out at the full screen', (tester) async {
      final events = items(3);
      events.forEach(thumbnailOnPhone);

      await pumpIn(tester, gallery(events));

      expect(
        [
          for (final image in tester.widgetList<MediaImage>(
            find.byType(MediaImage),
          ))
            image.shownAt,
        ],
        [screenWidth(tester) / 2, screenWidth(tester) / 2, screenWidth(tester)],
      );
    });

    testWidgets('two items sit side by side as squares', (tester) async {
      await pumpIn(tester, gallery(items(2)));

      final ratios = tester
          .widgetList<AspectRatio>(find.byType(AspectRatio))
          .map((a) => a.aspectRatio);
      expect(ratios, [1, 1]);
      expect(find.text('09:41'), findsOneWidget);
    });

    testWidgets('an odd one out spans the full width', (tester) async {
      await pumpIn(tester, gallery(items(3)));

      final ratios = tester
          .widgetList<AspectRatio>(find.byType(AspectRatio))
          .map((a) => a.aspectRatio);
      expect(ratios, [1, 1, 2]);
    });

    testWidgets('past four, the last tile counts the rest', (tester) async {
      await pumpIn(tester, gallery(items(6)));

      expect(find.byType(AspectRatio), findsNWidgets(4));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('a video in the gallery is marked as one', (tester) async {
      final events = [
        galleryItem('a', 0, 2),
        galleryItem('b', 1, 2, msgtype: MessageTypes.Video),
      ];
      for (final event in events) {
        thumbnailOnPhone(event);
      }

      await pumpIn(tester, gallery(events));

      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('tapping an item opens the gallery at that item', (
      tester,
    ) async {
      final events = items(3);
      final context = await pumpIn(tester, gallery(events));

      await tester.tap(find.byType(AspectRatio).at(1));

      final page = pushes.page(context) as GalleryViewerPage;
      expect(page.events, events);
      expect(page.initialIndex, 1);
    });

    testWidgets('a failed item sits in its place and retries when tapped', (
      tester,
    ) async {
      final saved = File('${server.root.path}/photo.png')
        ..writeAsBytesSync(onePixelPng);
      final failure = FailedMediaSend(
        gallery: const GalleryGroupRef(id: 'g', index: 1, count: 3),
        photo: ComposedImage(path: saved.path, name: 'photo.png', caption: ''),
      );
      await pumpIn(
        tester,
        gallery(
          [galleryItem('a', 0, 3), galleryItem('c', 2, 3)],
          failed: [failure],
        ),
      );

      await tester.tap(find.text('Retry'));

      expect(retried, [same(failure)]);
      expect(pushes.routes, isEmpty);
      expect(
        shownAt(tester, find.byType(GalleryFailedThumbnail)),
        screenWidth(tester) / 2,
      );
    });

    testWidgets('a failed item without a preview is a plain tile', (
      tester,
    ) async {
      const failure = FailedMediaSend(
        gallery: GalleryGroupRef(id: 'g', index: 1, count: 2),
      );
      await pumpIn(
        tester,
        gallery([galleryItem('a', 0, 2)], failed: [failure]),
      );

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an item still sending shows its preview and progress, and '
        'cannot be opened', (tester) async {
      final events = items(2);
      await pumpIn(tester, gallery(events, pending: sending(events.first)));

      await tester.tap(find.byType(AspectRatio).first);

      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );
      expect(spinner.value, 0.75);
      expect(pushes.routes, isEmpty);
    });
  });

  testWidgets('a photo on its way is decoded no wider than the screen', (
    tester,
  ) async {
    await pumpIn(
      tester,
      PendingAttachmentTile(pendingSend: sending(media('photo'))),
    );

    expect(shownAt(tester, find.byType(PendingAttachmentTile)), isNull);
  });
}
