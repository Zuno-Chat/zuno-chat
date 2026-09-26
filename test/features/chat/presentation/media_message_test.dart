import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/gallery_viewer_page.dart';
import 'package:zuno/core/matrix/image_viewer_page.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/send_progress.dart';
import 'package:zuno/core/matrix/video_viewer_page.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
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
      expect(find.byType(AttachmentProgressBar), findsOneWidget);
      expect(pushes.routes, isEmpty);
    });
  });

  group('VideoMessage', () {
    Event video({Map<String, Object?>? info}) => media(
      'clip',
      msgtype: MessageTypes.Video,
      info: info ?? const {'w': 1920, 'h': 1080, 'duration': 42000},
    );

    testWidgets('shows a play button and how long it runs', (tester) async {
      final event = video();
      thumbnailOnPhone(event);

      await pumpIn(
        tester,
        VideoMessage(event: event, mediaMeta: _meta, showTimeOverlay: true),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('00:42'), findsOneWidget);
      expect(find.text('09:41'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
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

      expect(find.text('00:42'), findsNothing);
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
      expect(find.text('00:42'), findsNothing);
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
      expect(find.byType(CircularProgressIndicator), findsWidgets);
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
      final failure = FailedMediaSend(
        gallery: const GalleryGroupRef(id: 'g', index: 1, count: 3),
        bytes: onePixelPng,
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
      expect(spinner.value, isNotNull);
      expect(pushes.routes, isEmpty);
    });
  });
}
