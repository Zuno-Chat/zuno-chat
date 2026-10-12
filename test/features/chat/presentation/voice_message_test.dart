import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;

import 'package:zuno/core/matrix/attachment_actions.dart';
import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/message_contents/voice_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_audio_player.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/pump_until.dart';

const _meta = MessageMeta(time: '09:41', own: false);

void main() {
  late AttachmentServer server;
  late FakeAudioPlatform audio;

  setUp(() async {
    server = installAttachmentServer();
    audio = await installFakeAudioPlatform();
  });

  Event voice({
    int? durationMs = 42000,
    List<Object?>? waveform = const [100, 600, 1024, 300],
  }) => buildTestEvent(
    server.room,
    eventId: r'$voice',
    senderId: '@bob:example.org',
    status: EventStatus.synced,
    content: {
      'msgtype': MessageTypes.Audio,
      'body': 'voice.ogg',
      'url': 'mxc://example.org/voice',
      'info': {'mimetype': 'audio/ogg', 'duration': ?durationMs},
      'org.matrix.msc3245.voice': <String, Object?>{},
      'org.matrix.msc1767.audio': {'waveform': ?waveform},
    },
  );

  String keyOf(Event event) => attachmentCacheKey(event, thumbnail: false);

  void alreadyOnPhone(Event event) =>
      AttachmentCache.instance.put(keyOf(event), server.served);

  Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
    await pumpRealAsync(
      tester,
      rounds: rounds,
      step: const Duration(milliseconds: 20),
    );
  }

  Future<void> pumpVoice(WidgetTester tester, Event event) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: VoiceMessage(event: event, own: false, meta: _meta),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  void voiceTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await settle(tester, rounds: 20);
      }
    });
  }

  Future<void> pressPlayPause(WidgetTester tester) async {
    await tester.tap(find.byType(InkWell));
    await settle(tester);
  }

  Future<void> tapWaveformAt(WidgetTester tester, double fraction) async {
    final bars = find.byType(CustomPaint).last;
    final box = tester.getRect(bars);
    await tester.tapAt(Offset(box.left + box.width * fraction, box.center.dy));
    await settle(tester);
  }

  Iterable<int> seeks() =>
      audio.named('seek').map((c) => (c.arguments as Map)['position'] as int);

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

    expect(audio.methods, containsAllInOrder(['setSourceBytes', 'resume']));
    expect(
      (audio.named('setSourceBytes').single.arguments as Map)['mimeType'],
      'audio/ogg',
    );
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(server.downloads, isEmpty);
  });

  Future<void> playFromServer(WidgetTester tester, Event event) async {
    await pumpVoice(tester, event);
    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => audio.named('resume').isNotEmpty,
      reason: 'the downloaded message to play',
    );
  }

  Future<Uint8List?> keptOnDisk(WidgetTester tester, Event event) async {
    Uint8List? kept;
    for (var i = 0; i < 50 && kept == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      kept = await tester.runAsync<Uint8List?>(() async {
        final file = await DiskAttachmentCache.instance.file(keyOf(event));
        return file == null ? null : await file.readAsBytes();
      });
    }
    return kept;
  }

  voiceTest('downloads a message the first time and keeps it', (tester) async {
    final event = voice();

    await playFromServer(tester, event);

    expect(await keptOnDisk(tester, event), server.served);
    expect(server.downloads, hasLength(1));
    expect(AttachmentCache.instance.get(keyOf(event)), server.served);
    expect(audio.methods, contains('resume'));
  });

  voiceTest('a played message is shared without downloading it again', (
    tester,
  ) async {
    final device = installDeviceFakes();
    final event = voice();
    await playFromServer(tester, event);
    await keptOnDisk(tester, event);

    await tester.runAsync(() => shareAttachments([event]));

    expect(device.shared, hasLength(1));
    expect(server.downloads, hasLength(1));
  });

  voiceTest('where the player needs a file, it plays the cached copy', (
    tester,
  ) async {
    ambientCapabilities = iosCapabilities;
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpUntil(
      tester,
      () => audio.named('resume').isNotEmpty,
      reason: 'the cached copy to play',
    );

    final source = audio.named('setSourceUrl').single.arguments as Map;
    expect(source['isLocal'], isTrue);
    expect(source['mimeType'], 'audio/ogg');
    expect(
      p.isWithin(
        '${server.cacheDirectory.path}/attachment_cache',
        source['url'] as String,
      ),
      isTrue,
    );
    expect(audio.methods, isNot(contains('setSourceBytes')));
    expect(server.temporaryDirectory.listSync(), isEmpty);
  });

  voiceTest('scrolling away while it downloads does not start it', (
    tester,
  ) async {
    await pumpVoice(tester, voice());

    await tester.tap(find.byType(InkWell));
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 20);

    expect(server.downloads, hasLength(1));
    expect(audio.methods, isNot(contains('setSourceBytes')));
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
    expect(audio.methods, isNot(contains('setSourceBytes')));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
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
      await settle(tester);
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
      await settle(tester);
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

    expect(audio.named('setSourceBytes'), hasLength(1));
    expect(audio.named('resume'), hasLength(2));
  });

  voiceTest('shows how far it has played', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    audio.positionMs = 5000;
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

    audio.reportDuration(60000);
    await settle(tester);
    audio.finishPlaying();
    await settle(tester);

    expect(find.text('1:00'), findsOneWidget);
  });

  voiceTest('finishing goes back to showing the full length', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    audio.positionMs = 42000;
    audio.finishPlaying();
    await settle(tester);

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

    expect(audio.methods, containsAllInOrder(['setSourceBytes', 'resume']));
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

    expect(audio.named('resume'), hasLength(1));
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
    await settle(tester);

    await tapWaveformAt(tester, 0.5);

    expect(audio.named('setSourceBytes'), hasLength(2));
    expect(audio.named('resume'), hasLength(2));
    expect(seeks().single, closeTo(21000, 500));
  });

  voiceTest('a waveform tap does nothing while the length is unknown', (
    tester,
  ) async {
    final event = voice(durationMs: null);
    alreadyOnPhone(event);
    await pumpVoice(tester, event);

    await tapWaveformAt(tester, 0.5);

    expect(audio.methods, isNot(contains('setSourceBytes')));
    expect(seeks(), isEmpty);
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
