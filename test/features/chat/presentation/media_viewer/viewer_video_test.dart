import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/media_viewer/video_playback.dart';
import 'package:zuno/features/chat/presentation/media_viewer/viewer_video.dart';

import '../../../../helpers/fake_attachments.dart';
import '../../../../helpers/fake_audio_session.dart';
import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/pump_until.dart';

void main() {
  late AttachmentServer server;
  late FakeVideoPlayer player;

  setUp(() {
    server = installAttachmentServer();
    player = installFakeVideoPlayer();
  });

  Event clip(String id) =>
      server.video(eventId: id, thumbnailId: '${id.substring(1)}-thumb');

  Future<void> pumpVideo(
    WidgetTester tester,
    Event event, {
    VideoPlayback? playback,
    bool controlsVisible = true,
    VoidCallback? onPlay,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: zunoViewerTheme,
      home: Scaffold(
        body: ViewerVideo(
          event: event,
          playback: playback,
          controlsVisible: controlsVisible,
          onPlay: onPlay ?? () {},
        ),
      ),
    ),
  );

  testWidgets('without a playback a video shows its thumbnail and Play, and '
      'downloads only the thumbnail', (tester) async {
    var plays = 0;
    final event = clip(r'$idle');

    await pumpVideo(tester, event, onPlay: () => plays++);
    await pumpUntil(
      tester,
      () => server.downloads.isNotEmpty,
      reason: 'the thumbnail download',
    );

    expect(
      server.downloads.where((url) => url.path.endsWith('/idle')),
      isEmpty,
    );
    await tester.tap(find.byTooltip('Play'));
    expect(plays, 1);
    expect(player.opened, isEmpty);
  });

  testWidgets('a video that did not load says so, and Try again loads it '
      'again', (tester) async {
    final event = clip(r'$gone');
    server.goneFromServer(event);
    final playback = VideoPlayback(
      event,
      muted: false,
      audio: fakeMediaAudioSession(FakeAudioSessionPort()),
    );
    addTearDown(playback.dispose);

    await pumpVideo(tester, event, playback: playback);
    await playback.start();
    await pumpUntil(
      tester,
      () => shows('Video did not load.'),
      reason: 'the download to fail',
    );
    final before = server.downloads
        .where((url) => url.path.endsWith('/gone'))
        .length;

    await tester.tap(find.text('Try again'));
    await pumpUntil(
      tester,
      () =>
          server.downloads.where((url) => url.path.endsWith('/gone')).length >
          before,
      reason: 'the second download',
    );
  });

  testWidgets('a playing video shows Pause while its controls show, and '
      'Pause pauses it', (tester) async {
    final event = clip(r'$playing');
    final playback = VideoPlayback(
      event,
      muted: false,
      audio: fakeMediaAudioSession(FakeAudioSessionPort()),
    );

    await pumpVideo(tester, event, playback: playback);
    await playback.start();
    await pumpUntil(
      tester,
      () => find.byTooltip('Pause').evaluate().isNotEmpty,
      reason: 'the video to play',
    );

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();

    expect(player.calls.last, 'pause');
    expect(find.byTooltip('Play'), findsOneWidget);
    playback.dispose();
  });

  testWidgets('a playing video hides its center button with the controls', (
    tester,
  ) async {
    final event = clip(r'$hidden');
    final playback = VideoPlayback(
      event,
      muted: false,
      audio: fakeMediaAudioSession(FakeAudioSessionPort()),
    );

    await pumpVideo(tester, event, playback: playback, controlsVisible: false);
    await playback.start();
    await pumpUntil(
      tester,
      () => playback.playing,
      reason: 'the video to play',
    );
    await tester.pump();

    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byTooltip('Play'), findsNothing);
    playback.dispose();
  });
}
