import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/media_audio_session.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_audio_session.dart';

void main() {
  late FakeAudioSessionPort port;
  late bool onCall;
  late _FakePlayback message;
  late _FakePlayback other;
  late _FakePlayback video;

  setUp(() {
    port = FakeAudioSessionPort();
    onCall = false;
    message = _FakePlayback();
    other = _FakePlayback();
    video = _FakePlayback(MediaSound.video);
  });

  MediaAudioSession session({bool ownsRecordingSession = true}) =>
      fakeMediaAudioSession(
        port,
        ownsRecordingSession: ownsRecordingSession,
        callHoldsAudio: () => onCall,
      );

  test('a voice message sets speech playback and takes the session', () async {
    await session().beginPlayback(message);

    expect(port.log, ['configure playback', 'active']);
  });

  test('a video takes the session for film playback', () async {
    await session().beginPlayback(video);

    expect(port.log, ['configure video', 'active']);
  });

  test('video playback pauses other audio and plays as a film on the media '
      'volume', () {
    final playback = videoPlaybackSession;

    expect(playback.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(playback.avAudioSessionMode, AVAudioSessionMode.moviePlayback);
    expect(
      playback.androidAudioAttributes?.contentType,
      AndroidAudioContentType.movie,
    );
    expect(playback.androidAudioAttributes?.usage, AndroidAudioUsage.media);
    expect(playback.androidAudioFocusGainType, AndroidAudioFocusGainType.gain);
  });

  test('starting a video pauses voice messages, and starting a voice message '
      'pauses the video', () async {
    final audio = session();
    await audio.beginPlayback(message);

    await audio.beginPlayback(video);
    expect(message.pauses, 1);
    expect(video.pauses, 0);

    await audio.beginPlayback(other);
    expect(video.pauses, 1);
  });

  test(
    'the session goes back once the message stops, so music resumes',
    () async {
      final audio = session();
      await audio.beginPlayback(message);

      await audio.endPlayback(message);

      expect(port.log, ['configure playback', 'active', 'inactive']);
    },
  );

  test('voice playback pauses other audio, lets it resume, and plays speech '
      'on the media volume', () {
    final playback = voicePlaybackSession;

    expect(playback.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(
      playback.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.none,
    );
    expect(playback.avAudioSessionMode, AVAudioSessionMode.spokenAudio);
    expect(
      playback.avAudioSessionSetActiveOptions,
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
    expect(playback.androidAudioAttributes!.usage, AndroidAudioUsage.media);
    expect(
      playback.androidAudioAttributes!.contentType,
      AndroidAudioContentType.speech,
    );
    expect(
      playback.androidAudioFocusGainType,
      AndroidAudioFocusGainType.gainTransient,
    );
  });

  test('recording uses the speaker or a headset microphone, and lets other '
      'audio resume after', () {
    final recording = voiceRecordingSession;

    expect(
      recording.avAudioSessionCategory,
      AVAudioSessionCategory.playAndRecord,
    );
    expect(
      recording.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp,
    );
    expect(
      recording.avAudioSessionSetActiveOptions,
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  });

  test('two messages share the session, and it goes back only when the last '
      'one stops', () async {
    final audio = session();
    await audio.beginPlayback(message);
    await audio.beginPlayback(other);

    await audio.endPlayback(message);
    expect(port.log, ['configure playback', 'active']);

    await audio.endPlayback(other);
    expect(port.log, ['configure playback', 'active', 'inactive']);
  });

  test('a message that never started changes nothing when it stops', () async {
    await session().endPlayback(message);

    expect(port.log, isEmpty);
  });

  test('during a call the session is left to the call', () async {
    onCall = true;
    final audio = session();

    await audio.beginPlayback(message);
    await audio.endPlayback(message);

    expect(port.log, isEmpty);
  });

  test('a message stopped by a call leaves the session to the call, and the '
      'next one after the call takes it again', () async {
    final audio = session();
    await audio.beginPlayback(message);
    onCall = true;
    await audio.endPlayback(message);
    onCall = false;

    await audio.beginPlayback(message);

    expect(port.log, [
      'configure playback',
      'active',
      'configure playback',
      'active',
    ]);
  });

  test(
    'a message still playing when the call ends takes the session then',
    () async {
      onCall = true;
      final audio = session();
      await audio.beginPlayback(message);
      onCall = false;

      await audio.callEnded();

      expect(port.log, ['configure playback', 'active']);
    },
  );

  test('a call ending with nothing playing leaves the session alone', () async {
    final audio = session();

    await audio.callEnded();

    expect(port.log, isEmpty);
  });

  test('recording takes the session for recording, and hands it back to a '
      'message still playing', () async {
    final audio = session();
    await audio.beginPlayback(message);
    await audio.beginRecording(#recorder);

    await audio.endRecording(#recorder);

    expect(port.log, [
      'configure playback',
      'active',
      'configure recording',
      'active',
      'configure playback',
      'active',
    ]);
  });

  test('where the recorder holds its own audio focus, recording leaves the '
      'session alone', () async {
    final audio = session(ownsRecordingSession: false);

    await audio.beginRecording(#recorder);
    await audio.endRecording(#recorder);

    expect(port.log, isEmpty);
  });

  test('an interruption or unplugged headphones pause every playing '
      'message, which then gives the session back itself', () async {
    final audio = session();
    await audio.beginPlayback(message);
    await audio.beginPlayback(other);

    port.interrupt();
    await pumpEventQueue();
    port.unplug();
    await pumpEventQueue();

    expect(message.pauses, 2);
    expect(other.pauses, 2);
    expect(port.log, ['configure playback', 'active']);
  });

  test(
    'a message that stopped is not paused by a later interruption',
    () async {
      final audio = session();
      await audio.beginPlayback(message);
      await audio.endPlayback(message);

      port.interrupt();
      await pumpEventQueue();

      expect(message.pauses, 0);
    },
  );

  test('a session the platform refuses is reported, and is tried again next '
      'time', () async {
    final audio = session();
    port.refuse = true;

    final reports = await reportsDuring(() => audio.beginPlayback(message));
    port.refuse = false;
    await audio.endPlayback(message);
    await audio.beginPlayback(message);

    expect(reports, ['media audio session']);
    expect(port.log, ['configure playback', 'configure playback', 'active']);
  });
}

class _FakePlayback implements MediaPlayback {
  _FakePlayback([this.sound = MediaSound.voice]);

  @override
  final MediaSound sound;
  int pauses = 0;

  @override
  Future<void> pause() async => pauses++;
}
