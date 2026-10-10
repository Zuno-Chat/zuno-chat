import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:zuno/features/chat/presentation/video_caption_composer_page.dart';

import '../../../helpers/fake_video_player.dart';
import '../../../helpers/route_launcher.dart';

void main() {
  late FakeVideoPlayer player;
  ComposedVideo? result;
  var closed = false;

  setUp(() {
    player = installFakeVideoPlayer();
    result = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: routeLauncher<ComposedVideo>(
          (_) => const VideoCaptionComposerPage(
            path: '/cache/clip.mp4',
            name: 'clip.mp4',
          ),
          onResult: (composed) {
            result = composed;
            closed = true;
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets('loads the picked file and shows it ready to play', (
    tester,
  ) async {
    await open(tester);

    expect(player.opened, ['file:///cache/clip.mp4']);
    expect(find.text('Add a caption'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('shows a spinner until the video loads', (tester) async {
    player.loadGate = Completer();
    await open(tester, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);

    player.loadGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer), findsOneWidget);
  });

  testWidgets('a tap plays it, another pauses it', (tester) async {
    await open(tester);

    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(player.calls, contains('play'));
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.byType(VideoPlayer));
    await tester.pump();
    expect(player.calls.last, 'pause');
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('sends the file with its size, length and trimmed caption', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '  at the lake ');
    await send(tester);

    expect(closed, isTrue);
    expect(result!.path, '/cache/clip.mp4');
    expect(result!.name, 'clip.mp4');
    expect(result!.caption, 'at the lake');
    expect((result!.width, result!.height), (1280, 720));
    expect(result!.durationMs, 42000);
  });

  testWidgets('sent before it loads, it claims no size or length', (
    tester,
  ) async {
    player.loadGate = Completer();
    await open(tester, settle: false);

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result!.width, isNull);
    expect(result!.height, isNull);
    expect(result!.durationMs, isNull);
  });

  testWidgets('a video the device cannot play says so and can still be '
      'sent', (tester) async {
    player.unplayable.add('clip.mp4');
    await open(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('This video cannot be previewed.'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);

    await send(tester);

    expect(result!.path, '/cache/clip.mp4');
    expect(result!.durationMs, isNull);
  });

  testWidgets('going back sends nothing', (tester) async {
    await open(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });
}
