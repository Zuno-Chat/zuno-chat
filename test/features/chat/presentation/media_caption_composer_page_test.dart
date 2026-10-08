import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/features/chat/presentation/media_caption_composer_page.dart';

import '../../../helpers/fake_video_player.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('single image: no page indicator, empty caption sends fine', (
    tester,
  ) async {
    List<ComposedMedia>? result;
    final items = [PickedImage(name: 'a.jpg', bytes: _onePixelPng)];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedMedia>>(
                MaterialPageRoute(
                  builder: (_) => MediaCaptionComposerPage(items: items),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    final image = (result!.single as ComposedImageResult).image;
    expect(image.name, 'a.jpg');
    expect(image.caption, '');
  });

  testWidgets(
    'multiple images: swipe, per-page caption, send preserves order',
    (tester) async {
      List<ComposedMedia>? result;
      final items = [
        PickedImage(name: 'first.jpg', bytes: _onePixelPng),
        PickedImage(name: 'second.jpg', bytes: _onePixelPng),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<ComposedMedia>>(
                  MaterialPageRoute(
                    builder: (_) => MediaCaptionComposerPage(items: items),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'first caption');
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'second caption');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(result, hasLength(2));
      final first = (result![0] as ComposedImageResult).image;
      final second = (result![1] as ComposedImageResult).image;
      expect(first.name, 'first.jpg');
      expect(first.caption, 'first caption');
      expect(second.name, 'second.jpg');
      expect(second.caption, 'second caption');
    },
  );

  testWidgets('removing the only remaining item pops with no result (cancel)', (
    tester,
  ) async {
    List<ComposedMedia>? result;
    var popped = false;
    final items = [PickedImage(name: 'only.jpg', bytes: _onePixelPng)];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedMedia>>(
                MaterialPageRoute(
                  builder: (_) => MediaCaptionComposerPage(items: items),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('removing one of several items drops it from the sent result', (
    tester,
  ) async {
    List<ComposedMedia>? result;
    final items = [
      PickedImage(name: 'removed.jpg', bytes: _onePixelPng),
      PickedImage(name: 'kept.jpg', bytes: _onePixelPng),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<ComposedMedia>>(
                MaterialPageRoute(
                  builder: (_) => MediaCaptionComposerPage(items: items),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect((result!.single as ComposedImageResult).image.name, 'kept.jpg');
  });

  group('with videos', () {
    late FakeVideoPlayer player;
    List<ComposedMedia>? result;

    setUp(() {
      player = installFakeVideoPlayer();
      result = null;
    });

    Future<void> open(WidgetTester tester, List<PickedMedia> items) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<ComposedMedia>>(
                  MaterialPageRoute(
                    builder: (_) => MediaCaptionComposerPage(items: items),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> swipeNext(WidgetTester tester) async {
      await tester.drag(find.byType(PageView), const Offset(-800, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('a photo and a video go out in order, the video with its '
        'size and length', (tester) async {
      await open(tester, [
        PickedImage(name: 'a.jpg', bytes: _onePixelPng),
        const PickedVideo(name: 'b.mp4', path: '/cache/b.mp4'),
      ]);
      expect(find.byTooltip('Send all'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'photo');
      await swipeNext(tester);
      expect(find.byType(VideoPlayer), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' video ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect((result![0] as ComposedImageResult).image.caption, 'photo');
      final video = (result![1] as ComposedVideoResult).video;
      expect(
        (video.path, video.name, video.caption),
        ('/cache/b.mp4', 'b.mp4', 'video'),
      );
      expect((video.width, video.height, video.durationMs), (1280, 720, 42000));
    });

    testWidgets('a video plays and pauses on tap', (tester) async {
      await open(tester, [
        const PickedVideo(name: 'b.mp4', path: '/cache/b.mp4'),
      ]);

      await tester.tap(find.byType(VideoPlayer));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      await tester.tap(find.byType(VideoPlayer));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(player.calls.where((c) => c == 'play'), hasLength(1));
    });

    testWidgets('a video off screen that cannot play raises no error, and '
        'says so once shown', (tester) async {
      player.unplayable.add('broken.mp4');
      await open(tester, [
        PickedImage(name: 'a.jpg', bytes: _onePixelPng),
        const PickedVideo(name: 'broken.mp4', path: '/cache/broken.mp4'),
      ]);

      expect(tester.takeException(), isNull);

      await swipeNext(tester);

      expect(find.text('This video cannot be previewed.'), findsOneWidget);
      await tester.tap(find.byTooltip('Send all'));
      await tester.pumpAndSettle();

      expect((result![1] as ComposedVideoResult).video.durationMs, isNull);
    });

    testWidgets('removing the last item steps back to the one before', (
      tester,
    ) async {
      await open(tester, [
        PickedImage(name: 'a.jpg', bytes: _onePixelPng),
        PickedImage(name: 'b.jpg', bytes: _onePixelPng),
        const PickedVideo(name: 'c.mp4', path: '/cache/c.mp4'),
      ]);
      await swipeNext(tester);
      await tester.enterText(find.byType(TextField), 'keep me');
      await swipeNext(tester);
      expect(find.text('3 of 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove this item'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'keep me',
      );

      await tester.tap(find.byTooltip('Send all'));
      await tester.pumpAndSettle();

      expect(result, hasLength(2));
      expect(result!.whereType<ComposedVideoResult>(), isEmpty);
    });
  });

  testWidgets('the floating call window keeps clear of the caption bar', (
    tester,
  ) async {
    final items = [PickedImage(name: 'a.jpg', bytes: _onePixelPng)];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push<List<ComposedMedia>>(
              MaterialPageRoute(
                builder: (_) => MediaCaptionComposerPage(items: items),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.byIcon(Icons.send_rounded),
        matching: find.byType(KeepClearArea),
      ),
      findsOneWidget,
    );
  });
}
