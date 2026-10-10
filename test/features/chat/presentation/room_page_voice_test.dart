import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_audio_player.dart';
import '../../../helpers/opus_caf.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/pump_until.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late Directory temp;
  late List<String> recorderCalls;
  late bool permitted;
  late Object? startError;
  late bool stopGivesPath;
  late bool sendFails;
  late bool recordingUnreadable;
  late List<http.Request> uploads;
  Map<Object?, Object?>? startArgs;
  String? recordingPath;
  MockStreamHandlerEventSink? recorderState;

  setUp(() async {
    await installFakeAudioPlatform();
    temp = Directory.systemTemp.createTempSync('zuno_voice_');
    recorderCalls = [];
    permitted = true;
    startError = null;
    stopGivesPath = true;
    sendFails = false;
    recordingUnreadable = false;
    uploads = [];
    startArgs = null;
    recordingPath = null;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, (call) async => temp.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(pathProvider, null);
      temp.deleteSync(recursive: true);
    });
  });

  Future<void> realWait(WidgetTester tester, int ms) async {
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms)),
    );
    await tester.pump(Duration(milliseconds: ms));
  }

  Future<void> drive(WidgetTester tester, {int turns = 20}) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await realWait(tester, 20);
    }
  }

  List<int> recordedBytes(String path) {
    if (recordingUnreadable) return [1, 2, 3];
    if (path.endsWith('.caf')) {
      return opusCaf(
        packets: [
          [1, 2, 3],
          [4, 5, 6],
        ],
      );
    }
    return [79, 103, 103, 83];
  }

  Future<void> openRoom(
    WidgetTester tester, {
    PlatformCapabilities? platform,
  }) async {
    ambientCapabilities = capabilitiesLike(
      platform ?? iosCapabilities,
      uploadForegroundService: false,
    );
    harness = RoomPageHarness(db: SendingFakeDatabaseApi());
    harness.respond = (request) {
      final path = request.url.path;
      if (path.contains('/upload')) {
        uploads.add(request);
        return sendFails
            ? http.Response(jsonEncode({'errcode': 'M_UNKNOWN'}), 500)
            : http.Response(
                jsonEncode({'content_uri': 'mxc://example.org/voice'}),
                200,
              );
      }
      return null;
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        recorderCalls.add(call.method);
        final args = call.arguments as Map?;
        switch (call.method) {
          case 'create':
            final events = EventChannel(
              'com.llfbandit.record/events/${args!['recorderId']}',
            );
            messenger.setMockStreamHandler(
              events,
              MockStreamHandler.inline(
                onListen: (_, sink) {
                  recorderState = sink;
                },
              ),
            );
            addTearDown(() => messenger.setMockStreamHandler(events, null));
            return null;
          case 'hasPermission':
            return permitted;
          case 'start':
            final error = startError;
            if (error != null) throw error;
            recordingPath = args!['path'] as String;
            startArgs = args;
            recorderState?.success(1);
            return null;
          case 'isRecording':
            return recordingPath != null;
          case 'getAmplitude':
            return {'current': -12.0, 'max': 0.0};
          case 'stop':
            final path = recordingPath;
            recordingPath = null;
            recorderState?.success(2);
            if (path == null || !stopGivesPath) return null;
            File(path).writeAsBytesSync(recordedBytes(path));
            return path;
        }
        return null;
      },
    );
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
  }

  Finder mic() => find.byKey(const ValueKey('mic'));

  Future<TestGesture> holdMic(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getCenter(mic()));
    await tester.pump(const Duration(milliseconds: 200));
    await drive(tester, turns: 3);
    return gesture;
  }

  Future<void> tapMic(
    WidgetTester tester, {
    bool settle = true,
    Duration hold = const Duration(milliseconds: 50),
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(mic()));
    await tester.pump(hold);
    await gesture.up();
    if (settle) {
      await drive(tester, turns: 3);
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Iterable<Map<String, Object?>> voiceMessages() =>
      harness.sent.where((s) => s.containsKey('org.matrix.msc3245.voice'));

  List<File> leftoverRecordings() => temp.listSync().whereType<File>().toList();

  bool recordingDone() =>
      recorderCalls.contains('stop') && leftoverRecordings().isEmpty;

  testWidgets('holding records, and letting go sends it as a voice '
      'message', (tester) async {
    await openRoom(tester);

    final gesture = await holdMic(tester);
    expect(recorderCalls, containsAll(['hasPermission', 'start']));
    expect(find.text('Slide up to cancel'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:01'), findsOneWidget);

    await realWait(tester, 350);
    await gesture.up();
    await pumpUntil(
      tester,
      () => voiceMessages().isNotEmpty && recordingDone(),
      reason: 'the voice message to be sent and its recording removed',
    );

    final voice = voiceMessages().single;
    expect(voice['msgtype'], 'm.audio');
    final audio = voice['org.matrix.msc1767.audio']! as Map<String, Object?>;
    expect(audio['duration'], greaterThanOrEqualTo(300));
    expect(audio['waveform'], isA<List<Object?>>());
    expect(find.text('Slide up to cancel'), findsNothing);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('sliding up and letting go throws it away', (tester) async {
    await openRoom(tester);

    final gesture = await holdMic(tester);
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(find.text('Release to cancel'), findsOneWidget);

    await realWait(tester, 350);
    await gesture.up();
    await pumpUntil(
      tester,
      () => recordingDone() && !shows('Release to cancel'),
      reason: 'the recording to be thrown away',
    );

    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
    expect(find.text('Release to cancel'), findsNothing);
  });

  testWidgets('a tap starts hands-free recording, and another sends it', (
    tester,
  ) async {
    await openRoom(tester);

    await tapMic(tester);
    expect(find.byTooltip('Cancel recording'), findsOneWidget);

    await realWait(tester, 200);
    await tapMic(tester);
    await pumpUntil(
      tester,
      () => voiceMessages().isNotEmpty,
      reason: 'the voice message to be sent',
    );

    expect(voiceMessages(), hasLength(1));
    expect(find.byTooltip('Cancel recording'), findsNothing);
  });

  testWidgets('a hold let go too soon keeps recording hands-free', (
    tester,
  ) async {
    await openRoom(tester);

    final gesture = await holdMic(tester);
    await gesture.up();
    await drive(tester, turns: 2);

    expect(find.byTooltip('Cancel recording'), findsOneWidget);
    expect(voiceMessages(), isEmpty);

    await tester.tap(find.byTooltip('Cancel recording'));
    await pumpUntil(
      tester,
      () =>
          recordingDone() &&
          find.byTooltip('Cancel recording').evaluate().isEmpty,
      reason: 'the recording to be thrown away',
    );

    expect(find.byTooltip('Cancel recording'), findsNothing);
    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('an interrupted hold throws the recording away', (tester) async {
    await openRoom(tester);

    final gesture = await holdMic(tester);
    await gesture.cancel();
    await pumpUntil(
      tester,
      () => recordingDone() && !shows('Slide up to cancel'),
      reason: 'the recording to be thrown away',
    );

    expect(find.text('Slide up to cancel'), findsNothing);
    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('a recording under a tenth of a second is not sent', (
    tester,
  ) async {
    await openRoom(tester);

    await tapMic(tester, settle: false, hold: const Duration(milliseconds: 20));
    await tapMic(tester, settle: false, hold: const Duration(milliseconds: 20));
    await pumpUntil(
      tester,
      recordingDone,
      reason: 'the short recording to be dropped',
    );

    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('without the microphone it says how to allow it', (tester) async {
    permitted = false;
    await openRoom(tester);

    await tapMic(tester);

    expect(
      find.text('Allow microphone access to record voice messages'),
      findsOneWidget,
    );
    expect(recorderCalls, isNot(contains('start')));
  });

  testWidgets('a recorder that will not start says so', (tester) async {
    startError = PlatformException(code: 'busy');
    await openRoom(tester);

    await tapMic(tester);

    expect(find.text('Recording did not start. Try again.'), findsOneWidget);
    expect(find.byTooltip('Cancel recording'), findsNothing);
  });

  testWidgets('a recorder that returns nothing sends nothing', (tester) async {
    stopGivesPath = false;
    await openRoom(tester);

    await tapMic(tester);
    await realWait(tester, 200);
    await tapMic(tester);
    await drive(tester);

    expect(voiceMessages(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed send says so', (tester) async {
    sendFails = true;
    await openRoom(tester);

    await tapMic(tester);
    await realWait(tester, 200);
    await tapMic(tester);
    await pumpUntil(
      tester,
      () => shows('Voice message not sent. Try again.'),
      reason: 'the failed send to be reported',
    );

    expect(find.text('Voice message not sent. Try again.'), findsOneWidget);
  });

  group('the recording format', () {
    Future<void> recordAndSend(
      WidgetTester tester, {
      required String awaiting,
      required bool Function() until,
    }) async {
      final gesture = await holdMic(tester);
      await realWait(tester, 350);
      await gesture.up();
      await pumpUntil(tester, until, reason: awaiting);
    }

    testWidgets('where the recorder writes Ogg, it records mono 48 kHz Opus at '
        '32 kbps to .ogg and sends the recording as it is', (tester) async {
      await openRoom(tester, platform: androidCapabilities);

      await recordAndSend(
        tester,
        awaiting: 'the voice message to be sent',
        until: () => voiceMessages().isNotEmpty,
      );

      expect(startArgs!['path'], endsWith('.ogg'));
      expect(startArgs!['sampleRate'], 48000);
      expect(startArgs!['numChannels'], 1);
      expect(startArgs!['bitRate'], 32000);
      expect(uploads.single.bodyBytes, [79, 103, 103, 83]);
      expect(voiceMessages(), hasLength(1));
    });

    testWidgets('where the recorder cannot write Ogg, it records mono 48 kHz '
        'Opus at 32 kbps and sends it as Ogg Opus', (tester) async {
      await openRoom(tester, platform: iosCapabilities);

      await recordAndSend(
        tester,
        awaiting: 'the voice message to be sent and its recording removed',
        until: () => voiceMessages().isNotEmpty && recordingDone(),
      );

      expect(startArgs!['path'], endsWith('.caf'));
      expect(startArgs!['sampleRate'], 48000);
      expect(startArgs!['numChannels'], 1);
      expect(startArgs!['bitRate'], 32000);
      final sent = uploads.single.bodyBytes;
      expect(String.fromCharCodes(sent.take(4)), 'OggS');
      expect(String.fromCharCodes(sent.skip(28).take(8)), 'OpusHead');
      final voice = voiceMessages().single;
      expect(voice['body'], 'Voice message.ogg');
      expect((voice['info']! as Map<String, Object?>)['mimetype'], 'audio/ogg');
      expect(leftoverRecordings(), isEmpty);
    });

    testWidgets('a recording that cannot be repackaged is not sent, and says '
        'so', (tester) async {
      recordingUnreadable = true;
      await openRoom(tester, platform: iosCapabilities);

      await recordAndSend(
        tester,
        awaiting: 'the failure to be reported and the recording removed',
        until: () =>
            shows('Voice message not sent. Try again.') && recordingDone(),
      );

      expect(uploads, isEmpty);
      expect(voiceMessages(), isEmpty);
      expect(find.text('Voice message not sent. Try again.'), findsOneWidget);
      expect(leftoverRecordings(), isEmpty);
    });
  });
}
