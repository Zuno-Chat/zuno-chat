import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/message_contents/voice_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';

import '../../../helpers/fake_attachments.dart';
import '../../../helpers/fake_audio_player.dart';
import '../../../helpers/fake_matrix.dart';

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
    List<int>? waveform = const [100, 600, 1024, 300],
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

  void alreadyOnPhone(Event event) =>
      AttachmentCache.instance.put('${event.eventId}:audio', server.served);

  Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 20));
    }
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

    expect(find.text('00:42'), findsOneWidget);
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

  voiceTest('downloads a message the first time and keeps it', (tester) async {
    final event = voice();
    await pumpVoice(tester, event);

    await tester.tap(find.byType(InkWell));
    await pumpWhileFetching(
      tester,
      rounds: 20,
      until: () => audio.named('resume').isNotEmpty,
    );

    expect(server.downloads, hasLength(1));
    expect(AttachmentCache.instance.get('${event.eventId}:audio'), isNotNull);
    expect(audio.methods, contains('resume'));
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
    await pumpWhileFetching(
      tester,
      rounds: 20,
      until: () => find.byType(SnackBar).evaluate().isNotEmpty,
    );

    expect(find.text('Voice message did not load. Try again.'), findsOneWidget);
    expect(audio.methods, isNot(contains('setSourceBytes')));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
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

    expect(find.text('00:05'), findsOneWidget);
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

    expect(find.text('01:00'), findsOneWidget);
  });

  voiceTest('finishing goes back to showing the full length', (tester) async {
    final event = voice();
    alreadyOnPhone(event);
    await pumpVoice(tester, event);
    await pressPlayPause(tester);

    audio.positionMs = 42000;
    audio.finishPlaying();
    await settle(tester);

    expect(find.text('00:42'), findsOneWidget);
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
