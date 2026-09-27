import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_audio_player.dart';
import '../../../helpers/platform_capabilities.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late Directory temp;
  late List<String> recorderCalls;
  late bool permitted;
  late Object? startError;
  late bool stopGivesPath;
  late bool sendFails;
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
    await tester.pump();
  }

  Future<void> drive(WidgetTester tester, {int turns = 20}) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await realWait(tester, 20);
    }
  }

  Future<void> openRoom(WidgetTester tester) async {
    ambientCapabilities = capabilitiesLike(
      iosCapabilities,
      uploadForegroundService: false,
    );
    harness = RoomPageHarness(db: SendingFakeDatabaseApi());
    harness.respond = (request) {
      final path = request.url.path;
      if (path.contains('/upload')) {
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
            File(path).writeAsBytesSync([79, 103, 103, 83]);
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

  Future<void> tapMic(WidgetTester tester, {bool settle = true}) async {
    final gesture = await tester.startGesture(tester.getCenter(mic()));
    await tester.pump(const Duration(milliseconds: 50));
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
    await drive(tester);

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
    await drive(tester);

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
    await drive(tester);

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
    await drive(tester);

    expect(find.byTooltip('Cancel recording'), findsNothing);
    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('an interrupted hold throws the recording away', (tester) async {
    await openRoom(tester);

    final gesture = await holdMic(tester);
    await gesture.cancel();
    await drive(tester);

    expect(find.text('Slide up to cancel'), findsNothing);
    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('a recording under a tenth of a second is not sent', (
    tester,
  ) async {
    await openRoom(tester);

    await tapMic(tester, settle: false);
    await tapMic(tester, settle: false);
    await drive(tester);

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
    await drive(tester);

    expect(find.text('Voice message not sent. Try again.'), findsOneWidget);
  });
}
