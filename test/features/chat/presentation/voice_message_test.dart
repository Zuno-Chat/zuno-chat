import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;

import 'package:zuno/core/matrix/attachment_actions.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/matrix/media_audio_session.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/chat/presentation/message_contents/voice_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_audio_player.dart';
import '../../../helpers/fake_audio_session.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/pump_until.dart';
import '../../../helpers/zuno_app.dart';

const _meta = MessageMeta(time: '09:41', own: false);

void main() {
  late AttachmentServer server;
  late List<String> log;
  late FakeAudioPlatform audio;
  late FakeAudioSessionPort port;
  late MediaAudioSession session;
  late bool onCall;

  setUp(() {
    server = installAttachmentServer();
    log = [];
    audio = installFakeAudioPlatform(log);
    onCall = false;
    port = FakeAudioSessionPort(log);
    session = fakeMediaAudioSession(port, callHoldsAudio: () => onCall);
  });

  Event voice({
    int? durationMs = 42000,
    List<Object?>? waveform = const [100, 600, 1024, 300],
    String? mimetype = 'audio/ogg',
  }) => buildTestEvent(
    server.room,
    eventId: r'$voice',
    senderId: '@bob:example.org',
    status: EventStatus.synced,
    content: {
      'msgtype': MessageTypes.Audio,
      'body': 'voice.ogg',
      'url': 'mxc://example.org/voice',
      'info': {'mimetype': ?mimetype, 'duration': ?durationMs},
      'org.matrix.msc3245.voice': <String, Object?>{},
      'org.matrix.msc1767.audio': {'waveform': ?waveform},
    },
  );

  String keyOf(Event event) => attachmentCacheKey(event, thumbnail: false);

  void alreadyOnPhone(Event event) =>
      AttachmentCache.instance.put(keyOf(event), server.served);

  Future<void> pumpVoice(WidgetTester tester, Event event) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaAudioSessionProvider.overrideWithValue(session)],
        child: inZunoApp(
          SizedBox(
            width: 300,
            child: VoiceMessage(event: event, own: false, meta: _meta),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumpAudioPlayerDisposal(tester);
  }

  void voiceTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await unmount(tester);
      }
    });
  }

  bool showsIcon(IconData icon) => find.byIcon(icon).evaluate().isNotEmpty;

  Future<void> pressPlayPause(WidgetTester tester) async {
    final playing = showsIcon(Icons.pause);
    final call = playing ? 'pause' : 'play';
    final calls = audio.named(call).length;
    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () =>
          audio.named(call).length > calls &&
          showsIcon(playing ? Icons.play_arrow : Icons.pause),
      reason: 'the player to $call',
    );
  }

  Future<void> tapWaveformAt(WidgetTester tester, double fraction) async {
    final bars = find.byType(CustomPaint).last;
    final box = tester.getRect(bars);
    await tester.tapAt(Offset(box.left + box.width * fraction, box.center.dy));
    await tester.pump();
  }

  Future<void> untilSessionGivenBack(WidgetTester tester) => pumpUntil(
    tester,
    () => log.contains('inactive') && showsIcon(Icons.play_arrow),
    reason: 'playback to stop and the session to be given back',
  );

  Iterable<int> seeks() => audio
      .named('seek')
      .map((position) => (position! as Duration).inMilliseconds);

  String loadedPath() =>
      Uri.parse(audio.named('load').single! as String).toFilePath();

  String cacheDirectory() => '${server.cacheDirectory.path}/attachment_cache';

  voiceTest('shows the length before it plays', (tester) async {
    await pumpVoice(tester, voice());

    expect(find.text('0:42'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  voiceTest('plays a message already on the phone without downloading it', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await pressPlayPause(tester);

    expect(audio.methods, containsAllInOrder(['load', 'play']));
    expect(p.isWithin(cacheDirectory(), loadedPath()), isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(server.downloads, isEmpty);
  });

  Future<void> playFromServer(WidgetTester tester, Event event) async {
    await pumpVoice(tester, event);
    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => audio.named('play').isNotEmpty,
      reason: 'the downloaded message to play',
    );
  }

  Future<Uint8List?> keptOnDisk(Event event) async =>
      (await DiskAttachmentCache.instance.file(keyOf(event)))?.readAsBytes();

  voiceTest('downloads a message the first time and keeps it', (tester) async {
    final event = voice();

    await playFromServer(tester, event);

    expect(await keptOnDisk(event), server.served);
    expect(server.downloads, hasLength(1));
    expect(AttachmentCache.instance.get(keyOf(event)), isNull);
    expect(audio.methods, contains('play'));
  });

  voiceTest('a played message is shared without downloading it again', (
    tester,
  ) async {
    final device = installDeviceFakes();
    final event = voice();
    await playFromServer(tester, event);

    await shareAttachments([event]);

    expect(device.shared, hasLength(1));
    expect(server.downloads, hasLength(1));
  });

  voiceTest('where the player reads the type from the file name, it plays '
      'the cached copy through a link named for it', (tester) async {
    ambientCapabilities = iosCapabilities;
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => audio.named('play').isNotEmpty,
      reason: 'the cached copy to play',
    );

    final path = loadedPath();
    expect(p.extension(path), '.ogg');
    expect(FileSystemEntity.isLinkSync(path), isTrue);
    expect(p.isWithin(cacheDirectory(), Link(path).targetSync()), isTrue);
  });

  voiceTest('a message that names no type is linked under the type its first '
      'bytes show', (tester) async {
    ambientCapabilities = iosCapabilities;
    server.served = Uint8List.fromList([0, 0, 0, 24, ...'ftypM4A '.codeUnits]);
    final event = voice(mimetype: null);
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => audio.named('play').isNotEmpty,
      reason: 'the downloaded message to play',
    );

    expect(p.extension(loadedPath()), '.m4a');
  });

  voiceTest('tapping play twice quickly loads it once and shows no error', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    final reports = await reportsDuring(() async {
      await tester.tap(find.byType(InkWell));
      await tester.tap(find.byType(InkWell));
      await pumpUntil(
        tester,
        () => audio.named('play').isNotEmpty && showsIcon(Icons.pause),
        reason: 'the message to play',
      );
    });

    expect(audio.named('load'), hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
    expect(reports, isEmpty);
  });

  voiceTest('takes the audio session before it plays and gives it back when '
      'paused, so other audio pauses and then resumes', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await pressPlayPause(tester);
    expect(log, containsAllInOrder(['configure playback', 'active', 'play']));

    await pressPlayPause(tester);
    await pumpUntil(
      tester,
      () => log.contains('inactive'),
      reason: 'the session to be given back',
    );
    expect(log, containsAllInOrder(['play', 'pause', 'inactive']));
  });

  voiceTest('gives the audio session back once the message finishes', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    audio.finishPlaying();
    await untilSessionGivenBack(tester);

    expect(log, containsAllInOrder(['play', 'inactive']));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  voiceTest('an interruption or unplugged headphones pause it before the '
      'session goes back', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    port.unplug();
    await untilSessionGivenBack(tester);

    expect(log, containsAllInOrder(['play', 'pause', 'inactive']));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  voiceTest('gives the audio session back when scrolled away mid-play', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    await unmount(tester);
    await pumpUntil(
      tester,
      () => log.contains('inactive'),
      reason: 'the session to be given back',
    );

    expect(log, containsAllInOrder(['play', 'inactive']));
  });

  voiceTest('during a call it plays without touching the call\'s audio', (
    tester,
  ) async {
    onCall = true;
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await pressPlayPause(tester);
    await pressPlayPause(tester);

    expect(log, ['load', 'play', 'pause']);
  });

  voiceTest('scrolling away while it downloads does not start it', (
    tester,
  ) async {
    final event = voice();
    await pumpVoice(tester, event);
    server.holdDownloads();
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await unmount(tester);
    server.releaseDownloads();
    await tester.pump();

    expect(await keptOnDisk(event), server.served);
    expect(log, isEmpty);
  });

  voiceTest('a message that does not load says so and does not play', (
    tester,
  ) async {
    final event = voice();
    server.goneFromServer(event);
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'the failure to be reported',
    );

    expect(find.text('Voice message did not load. Try again.'), findsOneWidget);
    expect(audio.methods, isNot(contains('load')));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  voiceTest('a message that does not load offline asks to check the '
      'connection', (tester) async {
    final event = voice();
    server.respond = (request) =>
        throw http.ClientException('offline', request.url);
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'the failure to be reported',
    );

    expect(
      find.text(
        'Voice message did not load. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });

  voiceTest('a message the player cannot play says so', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    audio.refusesToPlay = true;
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'the failure to be reported',
    );

    expect(find.text('Voice message did not load. Try again.'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  voiceTest('a message the player cannot play is reported once, as the play '
      'that failed', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    audio.refusesToPlay = true;
    await pumpVoice(tester, event);

    final reports = await reportsDuring(() async {
      await tester.tap(find.byType(InkWell));
      await pumpUntil(
        tester,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        reason: 'the failure to be reported',
      );
    });

    expect(reports, ['play voice message']);
  });

  voiceTest('the player failing once playing is reported as the player\'s', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    final reports = await reportsDuring(() async {
      audio.failPlaying();
      await pumpUntil(
        tester,
        () => log.contains('inactive'),
        reason: 'the failed player to give the session back',
      );
    });

    expect(reports, ['voice message player']);
  });

  voiceTest('pausing then playing again carries on from where it stopped', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await pressPlayPause(tester);
    await pressPlayPause(tester);
    expect(audio.methods, contains('pause'));
    await pressPlayPause(tester);

    expect(audio.named('load'), hasLength(1));
    expect(audio.named('play'), hasLength(2));
  });

  voiceTest('shows how far it has played', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    audio.position = const Duration(seconds: 5);
    await pressPlayPause(tester);

    expect(find.text('0:05'), findsOneWidget);
  });

  voiceTest('the player\'s own length wins over the one in the message', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);
    await pressPlayPause(tester);

    audio.reportDuration(const Duration(minutes: 1));
    audio.finishPlaying();
    await pumpUntil(
      tester,
      () => shows('1:00'),
      reason: 'the player\'s length to show once finished',
    );

    expect(find.text('1:00'), findsOneWidget);
  });

  voiceTest('finishing goes back to showing the full length', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    audio.position = const Duration(seconds: 42);
    audio.finishPlaying();
    await untilSessionGivenBack(tester);

    expect(find.text('0:42'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(
      tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter,
      isA<CustomPainter>().having(
        (p) => (p as dynamic).progress,
        'progress',
        0.0,
      ),
    );
  });

  voiceTest('tapping the waveform before playing starts it there', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await tapWaveformAt(tester, 0.5);
    await pumpUntil(
      tester,
      () => audio.named('play').isNotEmpty,
      reason: 'the message to play',
    );

    expect(audio.methods, containsAllInOrder(['load', 'seek', 'play']));
    expect(seeks().single, closeTo(21000, 500));
  });

  voiceTest('tapping the waveform while paused moves without playing', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);
    await pressPlayPause(tester);

    await tapWaveformAt(tester, 0.25);
    await pumpUntil(
      tester,
      () => seeks().isNotEmpty,
      reason: 'the message to move',
    );

    expect(audio.named('play'), hasLength(1));
    expect(seeks().single, closeTo(10500, 500));
  });

  voiceTest('tapping the waveform of a finished message plays it there', (
    tester,
  ) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);
    audio.finishPlaying();
    await pumpUntil(
      tester,
      () => seeks().isNotEmpty && showsIcon(Icons.play_arrow),
      reason: 'the finished message to rewind',
    );

    await tapWaveformAt(tester, 0.5);
    await pumpUntil(
      tester,
      () => audio.named('play').length == 2,
      reason: 'the message to play again',
    );

    expect(audio.named('load'), hasLength(1));
    expect(audio.named('play'), hasLength(2));
    expect(seeks().last, closeTo(21000, 500));
  });

  voiceTest('a waveform tap does nothing while the length is unknown', (
    tester,
  ) async {
    final event = voice(durationMs: null);
    await pumpVoice(tester, event);

    await tapWaveformAt(tester, 0.5);

    expect(server.downloads, isEmpty);
  });

  voiceTest('a message whose waveform changes redraws with the new one', (
    tester,
  ) async {
    await pumpVoice(tester, voice(waveform: const [100, 200]));

    await pumpVoice(tester, voice(waveform: const [900, 800, 700]));

    final painter = tester
        .widget<CustomPaint>(find.byType(CustomPaint).last)
        .painter;
    expect((painter as dynamic).samples, [900, 800, 700]);
  });

  List<int> drawnBars(WidgetTester tester) {
    final bars = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
    return (bars.painter as dynamic).samples as List<int>;
  }

  voiceTest('a waveform with a broken entry still draws the rest', (
    tester,
  ) async {
    await pumpVoice(tester, voice(waveform: const ['x', 300, 600]));

    expect(tester.takeException(), isNull);
    expect(drawnBars(tester), [300, 600]);
  });

  voiceTest('a very long waveform draws at most fifty bars', (tester) async {
    await pumpVoice(tester, voice(waveform: List.filled(20000, 512)));

    expect(drawnBars(tester), List.filled(50, 512));
  });

  voiceTest('without a waveform it shows a plain progress bar', (tester) async {
    await pumpVoice(tester, voice(waveform: null));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  group('normalizedAmplitude', () {
    test('maps -45 dB to silence and 0 dB to full, clamping outside', () {
      expect(normalizedAmplitude(-45), 0);
      expect(normalizedAmplitude(-22.5), 0.5);
      expect(normalizedAmplitude(0), 1);
      expect(normalizedAmplitude(-90), 0);
      expect(normalizedAmplitude(6), 1);
    });
  });

  group('resampleWaveform', () {
    test('no samples is a flat line of the requested width', () {
      expect(resampleWaveform([], buckets: 4), [0, 0, 0, 0]);
    });

    test('averages each bucket onto the 0..1024 scale', () {
      expect(resampleWaveform([0, 1, 0.5, 0.5], buckets: 2), [512, 512]);
    });

    test('stretches a short recording so every bucket has a sample', () {
      expect(resampleWaveform([1], buckets: 3), [1024, 1024, 1024]);
    });

    test('defaults to fifty bars', () {
      expect(resampleWaveform(List.filled(200, 0.25)), hasLength(50));
    });
  });
}
