import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/currently_open_room_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/share/inbound_share.dart';
import 'package:zuno/features/chat/presentation/image_caption_composer_page.dart';
import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import 'room_page_harness.dart';

class _GatedDb extends SendingFakeDatabaseApi {
  final gate = Completer<void>();

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    await gate.future;
    return super.getEventList(
      room,
      start: start,
      onlySending: onlySending,
      limit: limit,
    );
  }
}

void main() {
  late RoomPageHarness harness;
  late List<String> notificationCalls;
  late bool readMarkersFail;

  setUp(() {
    rootBundle.clear();
    notificationCalls = [];
    readMarkersFail = false;
  });

  RoomPageHarness makeHarness({StoredEventsFakeDatabaseApi? db}) {
    final harness = RoomPageHarness(db: db ?? SendingFakeDatabaseApi());
    harness.respond = (request) {
      if (readMarkersFail && request.url.path.endsWith('/read_markers')) {
        return http.Response(jsonEncode({'errcode': 'M_UNKNOWN'}), 500);
      }
      return null;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            notificationCalls.add(call.method);
            return call.method == 'initialize' ? true : null;
          },
        );
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
      notificationCalls.clear();

      goToBackground(tester);
      await harness.settle(tester);
      expect(container(tester).read(currentlyOpenRoomIdProvider), isNull);

      comeBack(tester);
      await harness.settle(tester);
      expect(
        container(tester).read(currentlyOpenRoomIdProvider),
        harness.room.id,
      );
      expect(notificationCalls, contains('cancel'));
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
    Future<String> recoveryWords() async {
      final text = await File('assets/wordlist/recovery_words.txt')
          .readAsString();
      return text
          .split('\n')
          .where((w) => w.trim().isNotEmpty)
          .take(12)
          .join(' ');
    }

    testWidgets('asks first, and Cancel keeps it unsent', (tester) async {
      final words = (await tester.runAsync(recoveryWords))!;
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
      final words = (await tester.runAsync(recoveryWords))!;
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
    late List<MethodCall> shareCalls;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('zuno_share_');
      shareCalls = [];
      ambientCapabilities = capabilitiesLike(
        androidCapabilities,
        nativeImageResize: false,
        uploadForegroundService: false,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const share = MethodChannel('zuno/share');
      messenger.setMockMethodCallHandler(share, (call) async {
        shareCalls.add(call);
        final names = (call.arguments as Map)['names'] as List;
        return [
          for (final name in names)
            (File('${temp.path}/$name')..writeAsBytesSync([1, 2, 3])).path,
        ];
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(share, null);
        temp.deleteSync(recursive: true);
      });
    });

    Future<void> openWithShare(WidgetTester tester, InboundShare share) async {
      harness = makeHarness();
      harness.respond = (request) => request.url.path.contains('/upload')
          ? http.Response(
              jsonEncode({'content_uri': 'mxc://example.org/shared'}),
              200,
            )
          : null;
      harness.db.events = [harness.message(r'$m1')];
      await tester.pumpWidget(
        await harness.app(
          home: RoomPage(room: harness.room, pendingShare: share),
        ),
      );
      await harness.drive(tester);
    }

    testWidgets('shared text waits in the composer', (tester) async {
      await openWithShare(tester, const InboundShare(text: 'look at this'));

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
      );

      expect(find.byType(ImageCaptionComposerPage), findsOneWidget);
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
      final db = _GatedDb();
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
