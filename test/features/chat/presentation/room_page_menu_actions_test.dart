import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late SendingFakeDatabaseApi db;
  late List<MethodCall> shortcutCalls;
  late Object? shortcutAnswer;
  late bool refuse;

  setUp(() {
    shortcutCalls = [];
    shortcutAnswer = true;
    refuse = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const shortcuts = MethodChannel('zuno/shortcuts');
    messenger.setMockMethodCallHandler(shortcuts, (call) async {
      shortcutCalls.add(call);
      final answer = shortcutAnswer;
      if (answer is Exception) throw answer;
      return answer;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shortcuts, null));
  });

  RoomPageHarness makeHarness() {
    db = SendingFakeDatabaseApi();
    final harness = RoomPageHarness(db: db);
    harness.respond = (request) {
      final path = request.url.path;
      if (refuse && (path.endsWith('/invite') || path.endsWith('/leave'))) {
        return http.Response(
          jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
          403,
        );
      }
      if (path.contains('/thumbnail/')) {
        return http.Response.bytes([1, 2, 3], 200);
      }
      return null;
    };
    harness.db.events = [harness.message(r'$m1')];
    return harness;
  }

  Future<void> openRoom(WidgetTester tester) async {
    harness = makeHarness();
    await harness.pumpRoomPage(tester);
  }

  Future<void> openPushedRoom(WidgetTester tester) async {
    harness = makeHarness();
    await tester.pumpWidget(
      await harness.app(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RoomPage(room: harness.room),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await harness.settle(tester);
  }

  Future<void> pick(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(item));
    await harness.settle(tester);
  }

  Iterable<http.Request> requestsEndingWith(String end) =>
      harness.httpRequests.where((r) => r.url.path.endsWith(end));

  group('Add members', () {
    Future<void> invite(WidgetTester tester, String username) async {
      await pick(tester, 'Add members');
      expect(find.text('Add members'), findsWidgets);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        username,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Invite'));
      await harness.settle(tester);
    }

    testWidgets('invites a username on this server', (tester) async {
      await openRoom(tester);

      await invite(tester, 'carol');

      final request = requestsEndingWith('/invite').single;
      expect(jsonDecode(request.body), {'user_id': '@carol:example.org'});
      expect(find.text('Invitation sent'), findsOneWidget);
    });

    testWidgets('a refused invitation says so', (tester) async {
      refuse = true;
      await openRoom(tester);

      await invite(tester, 'carol');

      expect(find.text('Invitation not sent. Try again.'), findsOneWidget);
    });

    testWidgets('Cancel invites nobody', (tester) async {
      await openRoom(tester);

      await pick(tester, 'Add members');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await harness.settle(tester);

      expect(requestsEndingWith('/invite'), isEmpty);
    });

    testWidgets('a direct chat has no Add members', (tester) async {
      harness = makeHarness();
      harness.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [harness.room.id],
        },
      );
      await harness.pumpRoomPage(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Add members'), findsNothing);
      expect(find.text('Chat info'), findsOneWidget);
      expect(find.text('Delete chat'), findsOneWidget);
    });
  });

  group('Add to home screen', () {
    testWidgets('asks the launcher to pin the room', (tester) async {
      await openRoom(tester);

      await pick(tester, 'Add to home screen');

      final pin = shortcutCalls.single;
      expect(pin.method, 'pinShortcut');
      final args = pin.arguments as Map;
      expect(args['roomId'], harness.room.id);
      expect(args['iconBytes'], isNull);
      expect(
        find.text('Confirm on your home screen to finish adding it'),
        findsOneWidget,
      );
    });

    testWidgets('carries the room picture as the icon', (tester) async {
      harness = makeHarness();
      harness.room.setState(
        buildTestEvent(
          harness.room,
          eventId: r'$avatar',
          senderId: '@bob:example.org',
          type: EventTypes.RoomAvatar,
          stateKey: '',
          content: {'url': 'mxc://example.org/pic'},
        ),
      );
      await harness.pumpRoomPage(tester);

      await pick(tester, 'Add to home screen');

      expect((shortcutCalls.single.arguments as Map)['iconBytes'], [1, 2, 3]);
    });

    testWidgets('a launcher without shortcuts says so', (tester) async {
      shortcutAnswer = false;
      await openRoom(tester);

      await pick(tester, 'Add to home screen');

      expect(
        find.text('This launcher does not support home screen shortcuts'),
        findsOneWidget,
      );
    });

    testWidgets('a failure says so', (tester) async {
      shortcutAnswer = PlatformException(code: 'boom');
      await openRoom(tester);

      await pick(tester, 'Add to home screen');

      expect(find.text('Shortcut not added. Try again.'), findsOneWidget);
    });
  });

  group('Reload messages', () {
    testWidgets('asks first, then reloads from scratch', (tester) async {
      await openRoom(tester);

      await pick(tester, 'Reload messages');
      expect(find.text('Reload messages?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await harness.settle(tester);

      expect(db.deletedTimelines, [harness.room.id]);
      expect(find.byType(MessageTile), findsOneWidget);
    });

    testWidgets('Cancel keeps what is there', (tester) async {
      await openRoom(tester);

      await pick(tester, 'Reload messages');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await harness.settle(tester);

      expect(db.deletedTimelines, isEmpty);
      expect(find.byType(MessageTile), findsOneWidget);
    });

    testWidgets('a failure says so and still shows the messages', (
      tester,
    ) async {
      harness = makeHarness();
      db.deleteTimelineError = StateError('database locked');
      await harness.pumpRoomPage(tester);

      await pick(tester, 'Reload messages');
      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await harness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Messages not reloaded. Try again.'), findsOneWidget);
      expect(find.byType(MessageTile), findsOneWidget);
    });
  });

  group('Leave room', () {
    testWidgets('asks first, leaves, and closes the room', (tester) async {
      await openPushedRoom(tester);

      await pick(tester, 'Leave room');
      expect(find.text('Leave room?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await harness.settle(tester);
      await harness.settle(tester);

      expect(requestsEndingWith('/leave'), hasLength(1));
      expect(find.byType(RoomPage), findsNothing);
    });

    testWidgets('Cancel stays in the room', (tester) async {
      await openPushedRoom(tester);

      await pick(tester, 'Leave room');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await harness.settle(tester);

      expect(requestsEndingWith('/leave'), isEmpty);
      expect(find.byType(RoomPage), findsOneWidget);
    });

    testWidgets('a refusal stays in the room', (tester) async {
      refuse = true;
      await openPushedRoom(tester);

      await pick(tester, 'Leave room');
      await tester.tap(find.widgetWithText(TextButton, 'Leave'));
      await harness.settle(tester);

      expect(find.byType(RoomPage), findsOneWidget);
    });
  });
}
