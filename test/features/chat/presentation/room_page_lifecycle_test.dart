import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/currently_open_room_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/share/inbound_share.dart';
import 'package:zuno/features/chat/presentation/image_caption_composer_page.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';
import 'package:zuno/features/chat/presentation/video_caption_composer_page.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_video_player.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/gated_timeline_database.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/pump_until.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late RecordedNotifications notifications;
  late bool readMarkersFail;

  setUp(() {
    rootBundle.clear();
    readMarkersFail = false;
  });

  RoomPageHarness makeHarness({
    StoredEventsFakeDatabaseApi? db,
    List<Override> overrides = const [],
  }) {
    final harness = RoomPageHarness(
      db: db ?? SendingFakeDatabaseApi(),
      overrides: overrides,
    );
    harness.respond = (request) {
      if (readMarkersFail && request.url.path.endsWith('/read_markers')) {
        return http.Response(jsonEncode({'errcode': 'M_UNKNOWN'}), 500);
      }
      return null;
    };
    notifications = installFakeLocalNotifications();
    return harness;
  }

  Future<void> openRoom(WidgetTester tester, {int messages = 1}) async {
    harness = makeHarness();
    harness.db.events = [
      for (var i = 0; i < messages; i++)
        harness.message(
          '\$m$i',
          body: 'message $i',
          at: DateTime(2026, 9, 20, 12).subtract(Duration(minutes: i)),
        ),
    ];
    await harness.pumpRoomPage(tester);
  }

  void goToBackground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void comeBack(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(RoomPage)));

  Iterable<Map<String, Object?>> typing() => harness.httpRequests
      .where((r) => r.url.path.contains('/typing/'))
      .map((r) => jsonDecode(r.body) as Map<String, Object?>);

  group('while the app is in the background', () {
    testWidgets('the room is no longer the open one, and comes back on '
        'return', (tester) async {
      await openRoom(tester);
      expect(
        container(tester).read(currentlyOpenRoomIdProvider),
        harness.room.id,
      );
      notifications.methods.clear();

      goToBackground(tester);
      await harness.settle(tester);
      expect(container(tester).read(currentlyOpenRoomIdProvider), isNull);

      comeBack(tester);
      await harness.settle(tester);
      expect(
        container(tester).read(currentlyOpenRoomIdProvider),
        harness.room.id,
      );
      expect(notifications.methods, contains('cancel'));
    });

    testWidgets('a read marker that failed is sent again on return', (
      tester,
    ) async {
      readMarkersFail = true;
      await openRoom(tester);
      int markers() =>
          harness.requests.where((p) => p.endsWith('/read_markers')).length;
      expect(markers(), 1);

      readMarkersFail = false;
      goToBackground(tester);
      await harness.settle(tester);
      comeBack(tester);
      await harness.settle(tester);

      expect(markers(), 2);
    });
  });

  group('typing', () {
    testWidgets('is announced while writing and withdrawn once cleared', (
      tester,
    ) async {
      await openRoom(tester);

      await tester.enterText(find.byType(TextField), 'hel');
      await harness.settle(tester);
      expect(typing().single, containsPair('typing', true));

      await tester.enterText(find.byType(TextField), '');
      await harness.settle(tester);
      expect(typing().last, {'typing': false});
    });

    testWidgets('is refreshed while writing goes on, and dropped after a '
        'pause', (tester) async {
      await openRoom(tester);

      await tester.enterText(find.byType(TextField), 'hel');
      await harness.settle(tester);
      await tester.enterText(find.byType(TextField), 'hell');
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump(const Duration(seconds: 4));
      await tester.enterText(find.byType(TextField), 'hello!');
      await tester.pump(const Duration(seconds: 3));
      await harness.settle(tester);
      expect(typing().where((t) => t['typing'] == true), hasLength(2));

      await tester.pump(const Duration(seconds: 6));
      await harness.settle(tester);
      expect(typing().last, {'typing': false});
    });

    testWidgets('is withdrawn when leaving mid-sentence', (tester) async {
      await openRoom(tester);

      await tester.enterText(find.byType(TextField), 'hel');
      await harness.settle(tester);
      await tester.pumpWidget(const SizedBox());
      await harness.settle(tester);

      expect(typing().last, {'typing': false});
    });
  });

  group('sending a recovery code', () {
    String recoveryWords() =>
        shippedRecoveryWordlist().words.take(12).join(' ');

    testWidgets('asks first, and Cancel keeps it unsent', (tester) async {
      final words = recoveryWords();
      await openRoom(tester);

      await tester.enterText(find.byType(TextField), words);
      await tester.pump();
      await tester.tap(find.byType(SendIcon));
      await harness.settle(tester);

      expect(find.text('Send your recovery code?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await harness.settle(tester);

      expect(harness.sent, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        words,
      );
    });

    testWidgets('Send anyway sends it', (tester) async {
      final words = recoveryWords();
      await openRoom(tester);

      await tester.enterText(find.byType(TextField), words);
      await tester.pump();
      await tester.tap(find.byType(SendIcon));
      await harness.settle(tester);
      await tester.tap(find.text('Send anyway'));
      await harness.settle(tester);

      expect(harness.sent.single['body'], words);
    });
  });

  group('scrolling back', () {
    testWidgets('offers a way back to the latest message', (tester) async {
      await openRoom(tester, messages: 40);
      expect(find.byTooltip('Scroll to latest'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await harness.settle(tester);
      expect(find.byTooltip('Scroll to latest'), findsOneWidget);

      await tester.tap(find.byTooltip('Scroll to latest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byTooltip('Scroll to latest'), findsNothing);
      expect(find.textContaining('message 0', findRichText: true), findsOne);
    });
  });

  group('a share from another app', () {
    late Directory temp;
    late Directory work;
    late List<MethodCall> shareCalls;
    late Set<String> unreadable;
    late PlatformException? copyFailure;
    late bool uploadsFail;
    late Completer<void>? probeGate;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('zuno_share_');
      work = Directory.systemTemp.createTempSync('zuno_share_work_');
      shareCalls = [];
      unreadable = {};
      copyFailure = null;
      uploadsFail = false;
      probeGate = null;
      installFakeVideoPlayer();
      ambientCapabilities = capabilitiesLike(
        androidCapabilities,
        nativeImageResize: false,
        uploadForegroundService: false,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const share = MethodChannel('zuno/share');
      const video = MethodChannel('zuno/video');
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(share, (call) async {
        shareCalls.add(call);
        if (copyFailure case final failure?) throw failure;
        final names = (call.arguments as Map)['names'] as List;
        return [
          for (final name in names)
            unreadable.contains(name)
                ? null
                : (File(
                    '${temp.path}/$name',
                  )..writeAsBytesSync([1, 2, 3])).path,
        ];
      });
      messenger.setMockMethodCallHandler(video, (call) async {
        final args = call.arguments as Map;
        switch (call.method) {
          case 'probe':
            await probeGate?.future;
            return {
              'width': 480,
              'height': 270,
              'durationMs': 5000,
              'bitrate': 400000,
              'videoCodec': 'video/avc',
              'audioCodec': 'audio/mp4a-latm',
            };
          case 'remux':
            File(args['input'] as String).copySync(args['output'] as String);
            return true;
          case 'thumbnail':
            return {
              'bytes': Uint8List.fromList(
                img.encodeJpg(img.Image(width: 48, height: 27)),
              ),
              'width': 48,
              'height': 27,
              'mimeType': 'image/jpeg',
            };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => work.path,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(share, null);
        messenger.setMockMethodCallHandler(video, null);
        messenger.setMockMethodCallHandler(pathProvider, null);
        temp.deleteSync(recursive: true);
        work.deleteSync(recursive: true);
      });
    });

    Future<void> openWithShare(
      WidgetTester tester,
      InboundShare share, {
      List<Override> overrides = const [],
      required String awaiting,
      required bool Function() until,
    }) async {
      harness = makeHarness(overrides: overrides);
      harness.respond = (request) {
        final path = request.url.path;
        if (path.contains('/download/')) {
          return http.Response.bytes(
            img.encodeJpg(img.Image(width: 48, height: 27)),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        if (!path.contains('/upload')) return null;
        return uploadsFail
            ? http.Response(
                jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'boom'}),
                500,
              )
            : http.Response(
                jsonEncode({'content_uri': 'mxc://example.org/shared'}),
                200,
              );
      };
      harness.db.events = [harness.message(r'$m1')];
      await tester.pumpWidget(
        await harness.app(
          home: RoomPage(room: harness.room, pendingShare: share),
        ),
      );
      await pumpUntil(tester, until, reason: awaiting);
    }

    int failedTiles() => find.byType(GalleryFailedThumbnail).evaluate().length;

    bool settledOn(Type page) {
      final found = find.byType(page).evaluate();
      return found.isNotEmpty &&
          ModalRoute.of(found.single)!.animation!.isCompleted;
    }

    List<String> copies() => [
      for (final file in temp.listSync()) file.uri.pathSegments.last,
    ];

    const sharedVideo = InboundShare(
      files: [
        SharedFile(
          uri: 'content://media/2',
          name: 'clip.mp4',
          mimeType: 'video/mp4',
        ),
      ],
    );

    SharedFile document(String name) => SharedFile(
      uri: 'content://docs/$name',
      name: name,
      mimeType: 'application/pdf',
    );

    Future<void> openWithSharedVideo(
      WidgetTester tester, {
      List<Override> overrides = const [],
    }) => openWithShare(
      tester,
      sharedVideo,
      overrides: overrides,
      awaiting: 'the caption screen for the video',
      until: () => settledOn(VideoCaptionComposerPage),
    );

    Future<void> sendFailingVideo(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Send'));
      await pumpUntil(
        tester,
        () => failedTiles() == 1,
        reason: 'the video to fail',
      );
    }

    testWidgets('shared text waits in the composer', (tester) async {
      await openWithShare(
        tester,
        const InboundShare(text: 'look at this'),
        awaiting: 'the shared text in the composer',
        until: () =>
            tester.widget<TextField>(find.byType(TextField)).controller!.text ==
            'look at this',
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'look at this');
      expect(field.controller!.selection.baseOffset, 'look at this'.length);
      expect(harness.sent, isEmpty);
    });

    testWidgets('a shared document is sent, and its copy removed', (
      tester,
    ) async {
      await openWithShare(
        tester,
        const InboundShare(
          files: [
            SharedFile(
              uri: 'content://docs/1',
              name: 'notes.txt',
              mimeType: 'text/plain',
            ),
          ],
        ),
        awaiting: 'the document to be sent and its copy removed',
        until: () => harness.sent.isNotEmpty && copies().isEmpty,
      );

      expect(shareCalls.single.method, 'copyToCache');
      expect(harness.sent.single['body'], 'notes.txt');
      expect(temp.listSync(), isEmpty);
    });

    testWidgets('a shared photo goes to the caption screen', (tester) async {
      await openWithShare(
        tester,
        const InboundShare(
          files: [
            SharedFile(
              uri: 'content://media/1',
              name: 'IMG_1.jpg',
              mimeType: 'image/jpeg',
            ),
          ],
        ),
        awaiting: 'the caption screen for the photo',
        until: () =>
            find.byType(ImageCaptionComposerPage).evaluate().isNotEmpty,
      );

      expect(find.byType(ImageCaptionComposerPage), findsOneWidget);
    });

    testWidgets('a shared video that fails keeps its copy, and a retry sends '
        'it and then removes the copy', (tester) async {
      final connection = StreamController<ConnectionStatus>.broadcast();
      addTearDown(connection.close);
      uploadsFail = true;
      await openWithSharedVideo(
        tester,
        overrides: [
          connectionStatusProvider.overrideWith((ref) => connection.stream),
        ],
      );
      connection.add(ConnectionStatus.online);
      await harness.drive(tester, turns: 2);

      expect(find.byType(VideoCaptionComposerPage), findsOneWidget);
      await sendFailingVideo(tester);

      expect(harness.sent, isEmpty);
      expect(find.text('Not sent. Tap to try again.'), findsOneWidget);
      expect(copies(), ['clip.mp4']);

      uploadsFail = false;
      connection.add(ConnectionStatus.noInternet);
      await harness.drive(tester, turns: 2);
      connection.add(ConnectionStatus.online);
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty && copies().isEmpty,
        reason: 'the video to go again and its copy to be removed',
      );

      expect(harness.sent.single['msgtype'], 'm.video');
      expect(temp.listSync(), isEmpty);
    });

    testWidgets('a retry that fails again keeps the copy for the next try', (
      tester,
    ) async {
      uploadsFail = true;
      await openWithSharedVideo(tester);
      await sendFailingVideo(tester);

      await tester.tap(find.byType(GalleryFailedThumbnail));
      await pumpUntil(
        tester,
        () => failedTiles() == 0,
        reason: 'the retry to start',
      );
      await pumpUntil(
        tester,
        () => failedTiles() == 1,
        reason: 'the retry to fail',
      );

      expect(harness.sent, isEmpty);
      expect(find.text('Not sent. Tap to try again.'), findsOneWidget);
      expect(copies(), hasLength(1));

      uploadsFail = false;
      await tester.tap(find.byType(GalleryFailedThumbnail));
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty && copies().isEmpty,
        reason: 'the video to go again and its copy to be removed',
      );

      expect(harness.sent.single['msgtype'], 'm.video');
      expect(temp.listSync(), isEmpty);
    });

    testWidgets('a retry still running when the rest of the share finishes '
        'keeps its copy until it is done', (tester) async {
      final pdfUpload = Completer<void>();
      var videoUploadsFail = true;
      await openWithShare(
        tester,
        InboundShare(files: [sharedVideo.files.single, document('b.pdf')]),
        awaiting: 'the caption screen for the video',
        until: () => settledOn(VideoCaptionComposerPage),
      );
      harness.respond = (request) async {
        if (!request.url.path.contains('/upload')) return null;
        final name = request.url.queryParameters['filename'] ?? '';
        if (name.endsWith('.pdf')) await pdfUpload.future;
        if (!name.endsWith('.pdf') && videoUploadsFail) {
          return http.Response(
            jsonEncode({'errcode': 'M_UNKNOWN', 'error': 'boom'}),
            500,
          );
        }
        return http.Response(
          jsonEncode({'content_uri': 'mxc://example.org/shared'}),
          200,
        );
      };
      await sendFailingVideo(tester);
      expect(find.text('Not sent. Tap to try again.'), findsOneWidget);

      videoUploadsFail = false;
      probeGate = Completer<void>();
      await tester.tap(find.byType(GalleryFailedThumbnail));
      await pumpUntil(
        tester,
        () => failedTiles() == 0,
        reason: 'the retry to start',
      );
      pdfUpload.complete();
      await pumpUntil(
        tester,
        () => harness.sent.isNotEmpty && copies().length == 1,
        reason: 'the document to be sent and its copy removed',
      );
      expect(copies(), ['clip.mp4']);

      probeGate!.complete();
      await pumpUntil(
        tester,
        () => harness.sent.length == 2 && copies().isEmpty,
        reason: 'the retried video to be sent and its copy removed',
      );

      expect(harness.sent.map((sent) => sent['msgtype']), [
        'm.file',
        'm.video',
      ]);
      expect(temp.listSync(), isEmpty);
    });

    testWidgets('leaving the chat removes a shared video kept for a retry', (
      tester,
    ) async {
      uploadsFail = true;
      await openWithSharedVideo(tester);
      await sendFailingVideo(tester);
      expect(copies(), hasLength(1));

      await tester.pumpWidget(const SizedBox());
      await pumpUntil(
        tester,
        () => copies().isEmpty,
        reason: 'the kept copy to be removed',
      );

      expect(temp.listSync(), isEmpty);
    });

    testWidgets('a shared file that cannot be opened says so, and the rest '
        'is sent', (tester) async {
      unreadable = {'broken.pdf'};
      await openWithShare(
        tester,
        InboundShare(files: [document('notes.pdf'), document('broken.pdf')]),
        awaiting: 'the readable file to be sent',
        until: () => harness.sent.isNotEmpty,
      );

      expect(
        find.text('One shared file could not be opened. Share it again.'),
        findsOneWidget,
      );
      expect(harness.sent.single['body'], 'notes.pdf');
    });

    testWidgets('shared files that fail to copy say how many, and nothing '
        'breaks', (tester) async {
      copyFailure = PlatformException(code: 'bad_arguments');
      await openWithShare(
        tester,
        InboundShare(files: [document('a.pdf'), document('b.pdf')]),
        awaiting: 'the failed copies to be reported',
        until: () =>
            shows('2 shared files could not be opened. Share them again.'),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('2 shared files could not be opened. Share them again.'),
        findsOneWidget,
      );
      expect(harness.sent, isEmpty);
    });
  });

  group('a room you cannot post in', () {
    testWidgets('says so instead of offering the composer', (tester) async {
      harness = makeHarness();
      harness.room.setState(
        buildTestEvent(
          harness.room,
          eventId: r'$pl',
          senderId: '@bob:example.org',
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          content: {
            'events_default': 50,
            'users': {'@bob:example.org': 100},
          },
        ),
      );
      harness.db.events = [harness.message(r'$m1')];
      await harness.pumpRoomPage(tester);

      expect(find.text('You cannot send messages here'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('while the room updates', () {
    testWidgets('a state change redraws the header', (tester) async {
      await openRoom(tester);

      harness.room.setState(
        buildTestEvent(
          harness.room,
          eventId: r'$name',
          senderId: '@bob:example.org',
          type: EventTypes.RoomName,
          stateKey: '',
          content: {'name': 'Hikers'},
        ),
      );
      harness.client.onRoomState.add((
        roomId: harness.room.id,
        state: harness.room.getState(EventTypes.RoomName)!,
      ));
      await harness.settle(tester);

      expect(find.text('Hikers'), findsOneWidget);
    });

    testWidgets('leaving before the messages load is harmless', (tester) async {
      final db = GatedTimelineFakeDatabaseApi();
      harness = makeHarness(db: db);
      db.events = [harness.message(r'$m1')];
      await tester.pumpWidget(
        await harness.app(home: RoomPage(room: harness.room)),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      db.gate.complete();
      await harness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(MessageTile), findsNothing);
    });
  });
}
