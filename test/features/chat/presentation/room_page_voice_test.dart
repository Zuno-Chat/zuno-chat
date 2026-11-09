import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart' show RecordState;
import 'package:zuno/core/matrix/media/media_audio_session.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/chat/data/unsent.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import '../../../helpers/app_lifecycle.dart';
import '../../../helpers/fake_audio_player.dart';
import '../../../helpers/fake_audio_session.dart';
import '../../../helpers/fake_emoji.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_screen_awake.dart';
import '../../../helpers/opus_caf.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/pump_until.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late FakeAudioPlatform audio;
  late Directory temp;
  late List<String> recorderCalls;
  late bool permitted;
  late bool promptAllows;
  late Object? startError;
  late bool stopGivesPath;
  late bool sendFails;
  late bool recordingUnreadable;
  late List<http.Request> uploads;
  Completer<void>? startGate;
  Map<Object?, Object?>? startArgs;
  Object? managesAudioSession;
  String? recordingPath;
  MockStreamHandlerEventSink? recorderState;

  setUp(() async {
    audio = installFakeAudioPlatform();
    managesAudioSession = null;
    temp = Directory.systemTemp.createTempSync('zuno_voice_');
    recorderCalls = [];
    permitted = true;
    promptAllows = false;
    startError = null;
    stopGivesPath = true;
    sendFails = false;
    recordingUnreadable = false;
    uploads = [];
    startGate = null;
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

  Future<void> drive(WidgetTester tester, {int turns = 20}) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump(const Duration(milliseconds: 70));
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
    bool overLauncher = false,
  }) async {
    ambientCapabilities = platform ?? iosCapabilities;
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      overrides: [
        mediaAudioSessionProvider.overrideWithValue(
          fakeMediaAudioSession(
            FakeAudioSessionPort(recorderCalls),
            ownsRecordingSession: ambientCapabilities.recorderNeedsAudioSession,
          ),
        ),
      ],
    );
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
            if (!permitted && args!['request'] == true) {
              permitted = promptAllows;
            }
            return permitted;
          case 'start':
            await startGate?.future;
            final error = startError;
            if (error != null) throw error;
            recordingPath = args!['path'] as String;
            startArgs = args;
            recorderState?.success(1);
            return null;
          case 'ios.manageAudioSession':
            managesAudioSession = args!['manageAudioSession'];
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
    if (overLauncher) {
      await harness.pumpRoomPageOverLauncher(tester);
    } else {
      await harness.pumpRoomPage(tester);
    }
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
    expect(find.text('0:01'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
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

    await tester.pump(const Duration(milliseconds: 350));
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

  testWidgets('sliding redraws the composer only when it crosses the cancel '
      'line', (tester) async {
    await openRoom(tester);
    final gesture = await holdMic(tester);
    Widget hint() => tester.widget(find.text('Slide up to cancel'));
    final before = hint();

    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(identical(hint(), before), isTrue);

    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(find.text('Release to cancel'), findsOneWidget);

    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(find.text('Slide up to cancel'), findsOneWidget);
    await gesture.cancel();
    await pumpUntil(tester, recordingDone, reason: 'the recording to end');
  });

  testWidgets('a tap starts hands-free recording, and another sends it', (
    tester,
  ) async {
    final toggles = installFakeScreenAwake().toggles;
    await openRoom(tester);

    await tapMic(tester);
    expect(find.byTooltip('Cancel recording'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tapMic(tester);
    await pumpUntil(
      tester,
      () => voiceMessages().isNotEmpty,
      reason: 'the voice message to be sent',
    );

    expect(voiceMessages(), hasLength(1));
    expect(find.byTooltip('Cancel recording'), findsNothing);
    expect(toggles, [true, false]);
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

  testWidgets('holding to record keeps the emoji list open, mic in place', (
    tester,
  ) async {
    await openRoom(tester);
    await showEmojiList(tester);
    final micAt = tester.getCenter(mic());

    final gesture = await holdMic(tester);
    expect(find.text('Slide up to cancel'), findsOneWidget);
    expect(find.byType(EmojiPicker), findsOneWidget);
    expect(tester.getCenter(mic()), micAt);

    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await pumpUntil(
      tester,
      () => voiceMessages().isNotEmpty && recordingDone(),
      reason: 'the voice message to be sent',
    );
    expect(find.byType(EmojiPicker), findsOneWidget);
  });

  group('with the keyboard open', () {
    Future<void> openRoomTyping(WidgetTester tester) async {
      await openRoom(tester);
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();
    }

    bool keyboardOpen(WidgetTester tester) => tester.testTextInput.isVisible;

    String draft(WidgetTester tester) => tester
        .widget<TextField>(find.byType(TextField, skipOffstage: false))
        .controller!
        .text;

    testWidgets('holding to record keeps it open, and so does sending', (
      tester,
    ) async {
      await openRoomTyping(tester);

      final gesture = await holdMic(tester);
      expect(find.text('Slide up to cancel'), findsOneWidget);
      expect(keyboardOpen(tester), isTrue);

      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await pumpUntil(
        tester,
        () => voiceMessages().isNotEmpty && recordingDone(),
        reason: 'the voice message to be sent',
      );

      expect(keyboardOpen(tester), isTrue);
    });

    testWidgets('a tap to record hands-free keeps it open', (tester) async {
      await openRoomTyping(tester);

      await tapMic(tester);
      expect(find.byTooltip('Cancel recording'), findsOneWidget);
      expect(keyboardOpen(tester), isTrue);

      await tester.pump(const Duration(milliseconds: 200));
      await tapMic(tester);
      await pumpUntil(
        tester,
        () => voiceMessages().isNotEmpty,
        reason: 'the voice message to be sent',
      );

      expect(keyboardOpen(tester), isTrue);
    });

    testWidgets('typing while recording leaves the hidden draft alone', (
      tester,
    ) async {
      await openRoomTyping(tester);

      await tapMic(tester);
      tester.testTextInput.enterText('typed blind');
      await tester.pump();

      expect(draft(tester), isEmpty);

      await tester.tap(find.byTooltip('Cancel recording'));
      await pumpUntil(
        tester,
        () =>
            recordingDone() &&
            find.byTooltip('Cancel recording').evaluate().isEmpty,
        reason: 'the recording to be thrown away',
      );
      tester.testTextInput.enterText('typed after');
      await tester.pump();

      expect(draft(tester), 'typed after');
    });
  });

  group('a recording something else stops', () {
    Finder deleteKept() => find.byTooltip('Delete');

    bool kept() => deleteKept().evaluate().isNotEmpty;

    Future<void> untilKept(WidgetTester tester) => pumpUntil(
      tester,
      () => kept() && recordingDone(),
      reason: 'the recording to stop and be kept',
    );

    Future<void> leaveAndComeBack(WidgetTester tester) async {
      moveLifecycleTo(tester.binding, AppLifecycleState.paused);
      await pumpUntil(
        tester,
        recordingDone,
        reason: 'the recording to stop while Zuno is away',
      );
      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> recordHandsFree(WidgetTester tester) async {
      await tapMic(tester);
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('leaving Zuno stops it and keeps it unsent, with its '
        'length', (tester) async {
      await openRoom(tester);
      await recordHandsFree(tester);

      await leaveAndComeBack(tester);
      expect(kept(), isTrue);

      expect(voiceMessages(), isEmpty);
      expect(uploads, isEmpty);
      expect(find.byTooltip('Cancel recording'), findsNothing);
      expect(find.text('0:02'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(mic(), findsNothing);
    });

    testWidgets('a kept recording is sent with the send button', (
      tester,
    ) async {
      await openRoom(tester);
      await recordHandsFree(tester);
      await leaveAndComeBack(tester);

      await tester.tap(find.byType(SendIcon));
      await pumpUntil(
        tester,
        () => voiceMessages().isNotEmpty && !kept(),
        reason: 'the kept recording to be sent',
      );

      final voice = voiceMessages().single;
      final sound = voice['org.matrix.msc1767.audio']! as Map<String, Object?>;
      expect(sound['duration'], greaterThanOrEqualTo(2000));
      expect(String.fromCharCodes(uploads.single.bodyBytes.take(4)), 'OggS');
      expect(mic(), findsOneWidget);
      expect(
        harness.container.read(unsentProvider).voiceOf(harness.room),
        isNull,
      );
    });

    testWidgets('a kept recording can be deleted unsent', (tester) async {
      await openRoom(tester);
      await recordHandsFree(tester);
      await leaveAndComeBack(tester);

      await tester.tap(deleteKept());
      await tester.pump(const Duration(milliseconds: 500));

      expect(kept(), isFalse);
      expect(mic(), findsOneWidget);
      expect(voiceMessages(), isEmpty);
      expect(
        harness.container.read(unsentProvider).voiceOf(harness.room),
        isNull,
      );
    });

    testWidgets('a kept recording plays from an Ogg copy that is gone once '
        'it is sent', (tester) async {
      await openRoom(tester, platform: androidCapabilities);
      await recordHandsFree(tester);
      await leaveAndComeBack(tester);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await pumpUntil(
        tester,
        () => audio.named('play').isNotEmpty,
        reason: 'the kept recording to play',
      );
      final played = Uri.parse(audio.named('load').single! as String);
      final copy = File(played.toFilePath());
      expect(copy.path, endsWith('.ogg'));
      expect(copy.readAsBytesSync(), [79, 103, 103, 83]);

      await tester.tap(find.byType(SendIcon));
      await pumpUntil(
        tester,
        () => voiceMessages().isNotEmpty && !copy.existsSync(),
        reason: 'the recording to be sent and its copy removed',
      );
      await pumpAudioPlayerDisposal(tester);
    });

    testWidgets('one reaching five minutes stops there and is kept, '
        'unsent', (tester) async {
      await openRoom(tester);
      await tapMic(tester);

      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(find.byTooltip('Cancel recording'), findsOneWidget);
      expect(recorderCalls, isNot(contains('stop')));

      await tester.pump(const Duration(seconds: 1));
      await untilKept(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('5:00'), findsOneWidget);
      expect(find.byTooltip('Cancel recording'), findsNothing);
      expect(voiceMessages(), isEmpty);
    });

    testWidgets('a held recording the system takes the touch from is kept', (
      tester,
    ) async {
      await openRoom(tester);

      final gesture = await holdMic(tester);
      await tester.pump(const Duration(seconds: 1));
      await gesture.cancel();
      await untilKept(tester);

      expect(find.text('Slide up to cancel'), findsNothing);
      expect(voiceMessages(), isEmpty);
    });

    testWidgets('the recorder pausing itself, as for a phone call, stops the '
        'recording and keeps it', (tester) async {
      await openRoom(tester);
      await recordHandsFree(tester);

      recorderState!.success(RecordState.pause.index);
      await untilKept(tester);

      expect(voiceMessages(), isEmpty);
      expect(find.byTooltip('Cancel recording'), findsNothing);
    });

    testWidgets('one stopped in its first tenth of a second keeps nothing', (
      tester,
    ) async {
      await openRoom(tester);

      await tapMic(tester, settle: false);
      await leaveAndComeBack(tester);

      expect(kept(), isFalse);
      expect(mic(), findsOneWidget);
      expect(voiceMessages(), isEmpty);
    });

    testWidgets('one stopped while the recorder is still starting stops as '
        'soon as it starts, and keeps nothing', (tester) async {
      final toggles = installFakeScreenAwake().toggles;
      await openRoom(tester);
      final starting = startGate = Completer<void>();

      await tapMic(tester);
      expect(recorderCalls, contains('start'));
      moveLifecycleTo(tester.binding, AppLifecycleState.paused);
      starting.complete();
      await pumpUntil(
        tester,
        recordingDone,
        reason: 'the recording to stop once started',
      );
      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(kept(), isFalse);
      expect(find.byTooltip('Cancel recording'), findsNothing);
      expect(mic(), findsOneWidget);
      expect(toggles, [true, false]);
    });

    testWidgets('a press after Zuno has left records nothing', (tester) async {
      await openRoom(tester);
      moveLifecycleTo(tester.binding, AppLifecycleState.paused);

      await tapMic(tester);
      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      await tester.pump();

      expect(recorderCalls, isNot(contains('start')));
      expect(find.byTooltip('Cancel recording'), findsNothing);
      expect(mic(), findsOneWidget);
      expect(kept(), isFalse);
    });

    testWidgets('leaving the chat keeps it, and it waits there', (
      tester,
    ) async {
      await openRoom(tester, overLauncher: true);
      await recordHandsFree(tester);

      Navigator.of(tester.element(mic())).pop();
      await pumpUntil(
        tester,
        () => recordingDone() && find.byType(RoomPage).evaluate().isEmpty,
        reason: 'the chat to close and its recording to stop',
      );
      await tester.tap(find.text('open chat'));
      await harness.settle(tester);

      expect(kept(), isTrue);
      expect(find.text('0:02'), findsOneWidget);
      expect(voiceMessages(), isEmpty);
    });

    testWidgets('the screen stays on while recording and sleeps once it '
        'stops', (tester) async {
      final toggles = installFakeScreenAwake().toggles;
      await openRoom(tester);

      await recordHandsFree(tester);
      expect(toggles, [true]);

      await leaveAndComeBack(tester);
      expect(toggles, [true, false]);
    });
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
      step: Duration.zero,
    );

    expect(voiceMessages(), isEmpty);
    expect(leftoverRecordings(), isEmpty);
  });

  testWidgets('without the microphone it says how to allow it, and a tap once '
      'allowed records', (tester) async {
    permitted = false;
    await openRoom(tester);

    await tapMic(tester);

    expect(
      find.text('Allow microphone access to record voice messages'),
      findsOneWidget,
    );
    expect(recorderCalls, isNot(contains('start')));

    permitted = true;
    ScaffoldMessenger.of(tester.element(mic())).removeCurrentSnackBar();
    await tester.pump();
    await tapMic(tester);

    expect(recorderCalls, contains('start'));
    expect(find.byTooltip('Cancel recording'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel recording'));
    await pumpUntil(tester, recordingDone, reason: 'the recording to end');
  });

  testWidgets('a hold that has to ask for the microphone records nothing, '
      'and the next hold records', (tester) async {
    permitted = false;
    promptAllows = true;
    await openRoom(tester);

    final asking = await holdMic(tester);
    await asking.cancel();
    await drive(tester, turns: 2);

    expect(recorderCalls, isNot(contains('start')));
    expect(find.text('Slide up to cancel'), findsNothing);
    expect(find.byTooltip('Cancel recording'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    final gesture = await holdMic(tester);
    expect(find.text('Slide up to cancel'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await pumpUntil(
      tester,
      () => voiceMessages().isNotEmpty && recordingDone(),
      reason: 'the voice message to be sent',
    );

    expect(voiceMessages(), hasLength(1));
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
    await tester.pump(const Duration(milliseconds: 200));
    await tapMic(tester);
    await pumpUntil(
      tester,
      () =>
          recorderCalls.contains('stop') &&
          find.byTooltip('Cancel recording').evaluate().isEmpty,
      reason: 'the recording to end',
    );

    expect(uploads, isEmpty);
    expect(voiceMessages(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failed send says so', (tester) async {
    sendFails = true;
    await openRoom(tester);

    await tapMic(tester);
    await tester.pump(const Duration(milliseconds: 200));
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
      await tester.pump(const Duration(milliseconds: 350));
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

    Future<void> asIos(Future<void> Function() body) async {
      final opened = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = opened;
      }
    }

    testWidgets('where the recorder leaves its audio session behind, the app '
        'sets the recording session and gives it back once sent', (
      tester,
    ) async {
      await openRoom(tester, platform: iosCapabilities);

      await asIos(
        () => recordAndSend(
          tester,
          awaiting: 'the voice message to be sent and the session given back',
          until: () =>
              voiceMessages().isNotEmpty && recorderCalls.contains('inactive'),
        ),
      );

      expect(managesAudioSession, isFalse);
      expect(
        recorderCalls,
        containsAllInOrder([
          'ios.manageAudioSession',
          'configure recording',
          'active',
          'start',
          'stop',
          'inactive',
        ]),
      );
    });

    testWidgets('a recording that fails to start gives the session back', (
      tester,
    ) async {
      startError = PlatformException(code: 'record');
      await openRoom(tester, platform: iosCapabilities);

      await asIos(() async {
        await tapMic(tester);
        await pumpUntil(
          tester,
          () => recorderCalls.contains('inactive'),
          reason: 'the session to be given back',
        );
      });

      expect(
        recorderCalls,
        containsAllInOrder(['configure recording', 'active', 'inactive']),
      );
    });

    testWidgets('where the recorder holds its own audio focus, the app leaves '
        'the session to it', (tester) async {
      await openRoom(tester, platform: androidCapabilities);

      await recordAndSend(
        tester,
        awaiting: 'the voice message to be sent',
        until: () => voiceMessages().isNotEmpty,
      );

      expect(recorderCalls, isNot(contains('configure recording')));
      expect(managesAudioSession, isNull);
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
