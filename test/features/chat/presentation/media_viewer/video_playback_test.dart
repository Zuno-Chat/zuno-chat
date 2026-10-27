import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/media_audio_session.dart';

import 'package:zuno/features/chat/presentation/media_viewer/video_playback.dart';

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

  Event clip(String id) => server.video(eventId: id);

  testWidgets('start loads, then plays', (tester) async {
    final playback = await startedPlayback(tester, clip(r'$start'));

    expect(player.calls, contains('play'));
    expect(playback.playing, isTrue);
    expect(playback.controller!.value.duration, const Duration(seconds: 42));
    playback.dispose();
  });

  testWidgets('togglePlay pauses and resumes', (tester) async {
    final playback = await startedPlayback(tester, clip(r'$toggle'));

    playback.togglePlay();
    await tester.pump();
    expect(player.calls.last, 'pause');
    expect(playback.playing, isFalse);

    playback.togglePlay();
    await tester.pump();
    expect(player.calls, contains('play'));
    expect(playback.playing, isTrue);
    playback.dispose();
  });

  testWidgets('muted sets the volume to 0, and back to 1', (tester) async {
    final playback = await startedPlayback(tester, clip(r'$mute'));

    playback.muted = true;
    await tester.pump();
    expect(player.calls.last, 'volume 0.0');

    playback.muted = false;
    await tester.pump();
    expect(player.calls.last, 'volume 1.0');
    playback.dispose();
  });

  testWidgets('a playback created muted starts silent', (tester) async {
    final playback = VideoPlayback(
      clip(r'$silent'),
      muted: true,
      audio: fakeMediaAudioSession(FakeAudioSessionPort()),
    );
    await playback.start();
    await pumpUntil(
      tester,
      () => player.calls.contains('play'),
      reason: 'the video to play',
    );

    final beforePlay = player.calls.sublist(0, player.calls.indexOf('play'));
    expect(
      beforePlay.lastWhere((call) => call.startsWith('volume')),
      'volume 0.0',
    );
    playback.dispose();
  });

  testWidgets('dispose disposes the player', (tester) async {
    final playback = await startedPlayback(tester, clip(r'$dispose'));

    playback.dispose();

    await pumpUntil(
      tester,
      () => player.calls.contains('dispose'),
      reason: 'the player to be disposed',
    );
  });

  group('sound', () {
    late FakeAudioSessionPort port;
    late MediaAudioSession audio;

    setUp(() {
      port = FakeAudioSessionPort();
      audio = fakeMediaAudioSession(port);
    });

    testWidgets('the player leaves audio focus to the app', (tester) async {
      final playback = await startedPlayback(
        tester,
        clip(r'$focus'),
        audio: audio,
      );

      expect(player.calls, contains('mixWithOthers true'));
      playback.dispose();
    });

    testWidgets('playing with sound holds the media session, and pausing '
        'gives it back', (tester) async {
      final playback = await startedPlayback(
        tester,
        clip(r'$session'),
        audio: audio,
      );
      expect(port.log, ['configure video', 'active']);

      playback.togglePlay();
      await tester.pump();
      expect(port.log.last, 'inactive');

      playback.dispose();
    });

    testWidgets('muting gives the session back, and unmuting takes it again', (
      tester,
    ) async {
      final playback = await startedPlayback(
        tester,
        clip(r'$muting'),
        audio: audio,
      );

      playback.muted = true;
      await tester.pump();
      expect(port.log.last, 'inactive');

      playback.muted = false;
      await tester.pump();
      expect(port.log.last, 'active');

      playback.dispose();
    });

    testWidgets('a muted video leaves the session alone', (tester) async {
      final playback = await startedPlayback(
        tester,
        clip(r'$silent-session'),
        muted: true,
        audio: audio,
      );

      expect(port.log, isEmpty);
      playback.dispose();
    });

    testWidgets('an interruption pauses the video', (tester) async {
      final playback = await startedPlayback(
        tester,
        clip(r'$interrupted'),
        audio: audio,
      );

      port.interrupt();
      await tester.pump();

      expect(player.calls.last, 'pause');
      expect(playback.playing, isFalse);
      playback.dispose();
    });
  });
}
