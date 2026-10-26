import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/features/chat/presentation/media_caption_composer_page.dart';

import '../../../helpers/fake_video_player.dart';
import '../../../helpers/pump_until.dart';
import '../../../helpers/route_launcher.dart';

void main() {
  late FakeVideoPlayer player;
  List<ComposedMedia>? result;
  var closed = false;

  setUp(() {
    player = installFakeVideoPlayer();
    result = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester, List<PickedMedia> items) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: routeLauncher<List<ComposedMedia>>(
          (_) => MediaCaptionComposerPage(items: items),
          onResult: (composed) {
            result = composed;
            closed = true;
          },
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

  PickedImage photo(String name) =>
      PickedImage(name: name, path: '/picked/$name');

  testWidgets('single image: no page indicator, empty caption sends fine', (
    tester,
  ) async {
    await open(tester, [photo('a.jpg')]);

    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    final image = (result!.single as ComposedImageResult).image;
    expect(image.name, 'a.jpg');
    expect(image.caption, '');
  });

  testWidgets('removing the only remaining item pops with no result (cancel)', (
    tester,
  ) async {
    await open(tester, [photo('only.jpg')]);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('removing one of several items drops it from the sent result', (
    tester,
  ) async {
    await open(tester, [photo('removed.jpg'), photo('kept.jpg')]);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect((result!.single as ComposedImageResult).image.name, 'kept.jpg');
  });

  testWidgets('a photo and a video go out in order, each with its own '
      'caption, the video with its size and length', (tester) async {
    await open(tester, [
      photo('a.jpg'),
      const PickedVideo(name: 'b.mp4', path: '/cache/b.mp4'),
    ]);
    expect(find.byTooltip('Send all'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'photo');
    await swipeNext(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' video ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final image = (result![0] as ComposedImageResult).image;
    expect((image.name, image.caption), ('a.jpg', 'photo'));
    final video = (result![1] as ComposedVideoResult).video;
    expect(
      (video.path, video.name, video.caption),
      ('/cache/b.mp4', 'b.mp4', 'video'),
    );
    expect((video.width, video.height, video.durationMs), (1280, 720, 42000));
  });

  testWidgets('a video off screen that cannot play raises no error, and '
      'says so once shown', (tester) async {
    player.unplayable.add('broken.mp4');
    await open(tester, [
      photo('a.jpg'),
      const PickedVideo(name: 'broken.mp4', path: '/cache/broken.mp4'),
    ]);

    expect(tester.takeException(), isNull);

    await swipeNext(tester);

    expect(find.text('This video cannot be previewed.'), findsOneWidget);
    await tester.tap(find.byTooltip('Send all'));
    await tester.pumpAndSettle();

    expect((result![1] as ComposedVideoResult).video.durationMs, isNull);
  });

  PickedVideo clip(String name) =>
      PickedVideo(name: name, path: '/cache/$name');

  List<String> opened() => [
    for (final uri in player.opened) uri.split('/').last,
  ];

  int disposed() => player.calls.where((c) => c == 'dispose').length;

  int playersHeld() => player.opened.length - disposed();

  Future<void> untilDisposed(WidgetTester tester, int count) => pumpUntil(
    tester,
    () => disposed() >= count,
    reason: '$count players to be let go',
  );

  testWidgets('only the video on screen holds a player', (tester) async {
    await open(tester, [clip('a.mp4'), clip('b.mp4'), clip('c.mp4')]);

    expect(opened(), ['a.mp4']);
    expect(playersHeld(), 1);

    await swipeNext(tester);
    await untilDisposed(tester, 1);

    expect(opened(), ['a.mp4', 'b.mp4']);
    expect(playersHeld(), 1);
    expect(find.byType(VideoPlayer), findsOneWidget);
  });

  testWidgets('a photo on screen holds no player', (tester) async {
    await open(tester, [photo('a.jpg'), clip('b.mp4')]);

    expect(opened(), isEmpty);

    await swipeNext(tester);
    await tester.drag(find.byType(PageView), const Offset(800, 0));
    await tester.pumpAndSettle();

    await untilDisposed(tester, 1);

    expect(find.text('1 of 2'), findsOneWidget);
    expect(playersHeld(), 0);
  });

  testWidgets('a video swiped past keeps its size and length, one never '
      'shown claims none', (tester) async {
    await open(tester, [clip('a.mp4'), clip('b.mp4'), clip('c.mp4')]);

    await swipeNext(tester);
    await tester.tap(find.byTooltip('Send all'));
    await tester.pumpAndSettle();

    final sizes = [
      for (final ComposedVideoResult(:video)
          in result!.cast<ComposedVideoResult>())
        (video.width, video.height, video.durationMs),
    ];
    expect(sizes, [(1280, 720, 42000), (1280, 720, 42000), (null, null, null)]);
  });

  testWidgets('removing the video on screen lets its player go', (
    tester,
  ) async {
    await open(tester, [clip('a.mp4'), photo('b.jpg')]);

    await tester.tap(find.byTooltip('Remove this item'));
    await tester.pumpAndSettle();
    await untilDisposed(tester, 1);

    expect(playersHeld(), 0);
    expect(find.text('Add a caption'), findsOneWidget);
  });

  testWidgets('closing the screen lets the player go', (tester) async {
    await open(tester, [clip('a.mp4'), clip('b.mp4')]);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await untilDisposed(tester, 1);

    expect(closed, isTrue);
    expect(playersHeld(), 0);
  });

  testWidgets('removing the last item steps back to the one before', (
    tester,
  ) async {
    await open(tester, [
      photo('a.jpg'),
      photo('b.jpg'),
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
}
