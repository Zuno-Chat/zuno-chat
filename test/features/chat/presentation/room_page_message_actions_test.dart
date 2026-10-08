import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late List<String?> copied;
  late bool refuse;

  setUp(() {
    rootBundle.clear();
    copied = [];
    refuse = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String?);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Event own(String id, String body) => buildTestEvent(
    harness.room,
    eventId: id,
    senderId: '@me:example.org',
    originServerTs: DateTime(2026, 9, 20, 12, 5),
    status: EventStatus.synced,
    content: {'msgtype': 'm.text', 'body': body},
  );

  Future<void> openRoom(
    WidgetTester tester,
    List<Event> Function() events,
  ) async {
    harness = RoomPageHarness(db: SendingFakeDatabaseApi());
    harness.respond = (request) {
      final path = request.url.path;
      if (path.contains('/state/$liveLocationStateType/')) {
        return http.Response(jsonEncode({'event_id': r'$cleared'}), 200);
      }
      if (path.contains('/redact/') || path.contains('/send/m.reaction/')) {
        return refuse
            ? http.Response(
                jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
                403,
              )
            : http.Response(jsonEncode({'event_id': r'$done'}), 200);
      }
      if (path.contains('/media/') && path.contains('/download/')) {
        return http.Response(
          jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
          404,
        );
      }
      return null;
    };
    harness.db.events = events();
    await harness.pumpRoomPage(tester);
  }

  Future<void> openActions(WidgetTester tester, String body) async {
    await tester.longPress(find.textContaining(body, findRichText: true).first);
    await harness.settle(tester);
  }

  Future<void> tapAction(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ListTile, label));
    await harness.settle(tester);
  }

  Future<void> sendTyped(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byType(SendIcon));
    await harness.settle(tester);
  }

  Iterable<http.Request> requestsTo(String part) =>
      harness.httpRequests.where((r) => r.url.path.contains(part));

  group('reply', () {
    testWidgets('quotes the message and sends the answer as a reply', (
      tester,
    ) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tapAction(tester, 'Reply');

      expect(find.text('Replying to Bob'), findsOneWidget);
      await sendTyped(tester, 'hi back');

      final sent = harness.sent.single;
      expect(sent['body'], contains('hi back'));
      expect(
        ((sent['m.relates_to']! as Map)['m.in_reply_to'] as Map)['event_id'],
        r'$m1',
      );
      expect(find.text('Replying to Bob'), findsNothing);
    });

    testWidgets('can be dropped before sending', (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tapAction(tester, 'Reply');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();

      expect(find.text('Replying to Bob'), findsNothing);
    });
  });

  group('edit', () {
    testWidgets('fills the composer and sends a replacement', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'teh plan')]);

      await openActions(tester, 'teh plan');
      await tapAction(tester, 'Edit');

      expect(find.text('Editing message'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'teh plan',
      );

      await sendTyped(tester, 'the plan');

      final sent = harness.sent.single;
      expect((sent['m.new_content']! as Map)['body'], 'the plan');
      expect((sent['m.relates_to']! as Map)['rel_type'], 'm.replace');
      expect((sent['m.relates_to']! as Map)['event_id'], r'$mine');
    });

    testWidgets('cancelling clears the composer', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'teh plan')]);

      await openActions(tester, 'teh plan');
      await tapAction(tester, 'Edit');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();

      expect(find.text('Editing message'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });

    testWidgets("someone else's message cannot be edited", (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');

      expect(find.widgetWithText(ListTile, 'Edit'), findsNothing);
    });
  });

  group('delete', () {
    testWidgets('asks first, then deletes for everyone', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'oops')]);

      await openActions(tester, 'oops');
      await tapAction(tester, 'Delete');
      expect(find.text('Delete message?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await harness.settle(tester);

      expect(requestsTo('/redact/'), hasLength(1));
      expect(
        requestsTo('/redact/').single.url.path,
        contains(Uri.encodeComponent(r'$mine')),
      );
    });

    testWidgets('a live location ends its share before it is deleted', (
      tester,
    ) async {
      const me = '@me:example.org';
      final now = DateTime.now();
      await openRoom(
        tester,
        () => [
          buildTestEvent(
            harness.room,
            eventId: r'$live',
            senderId: me,
            originServerTs: now,
            status: EventStatus.synced,
            content: liveLocationStartContent(
              shareId: 'share1',
              endsAt: now.add(const Duration(hours: 1)),
              duration: LiveLocationDuration.hour,
            ),
          ),
        ],
      );
      harness.room.setState(
        buildTestEvent(
          harness.room,
          eventId: r'$state',
          senderId: me,
          type: liveLocationStateType,
          stateKey: me,
          originServerTs: now,
          content: LiveShareState(
            shareId: 'share1',
            deviceId: 'LAPTOP',
            endsAt: now.add(const Duration(hours: 1)),
          ).toContent(),
        ),
      );

      await openActions(tester, 'Live location ended');
      await tapAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await harness.settle(tester);

      final paths = [for (final r in harness.httpRequests) r.url.path];
      final cleared = paths.indexWhere(
        (path) => path.contains('/state/$liveLocationStateType/'),
      );
      final deleted = paths.indexWhere((path) => path.contains('/redact/'));
      expect(cleared, isNonNegative);
      expect(deleted, greaterThan(cleared));
    });

    testWidgets('Cancel keeps it', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'oops')]);

      await openActions(tester, 'oops');
      await tapAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await harness.settle(tester);

      expect(requestsTo('/redact/'), isEmpty);
    });

    testWidgets('a refusal says so', (tester) async {
      refuse = true;
      await openRoom(tester, () => [own(r'$mine', 'oops')]);

      await openActions(tester, 'oops');
      await tapAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await harness.settle(tester);

      expect(find.text('Message not deleted. Try again.'), findsOneWidget);
    });
  });

  testWidgets('Copy copies the text without the reply quote', (tester) async {
    await openRoom(
      tester,
      () => [
        harness.message(
          r'$m1',
          body: '> <@me:example.org> earlier\n\nthe answer',
        ),
      ],
    );

    await openActions(tester, 'the answer');
    await tapAction(tester, 'Copy');

    expect(copied, ['the answer']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a live location offers no Copy', (tester) async {
    final now = DateTime.now();
    await openRoom(
      tester,
      () => [
        buildTestEvent(
          harness.room,
          eventId: r'$live',
          senderId: '@bob:example.org',
          originServerTs: now,
          status: EventStatus.synced,
          content: liveLocationStartContent(
            shareId: 'share1',
            endsAt: now.add(const Duration(hours: 1)),
            duration: LiveLocationDuration.hour,
          ),
        ),
      ],
    );

    await openActions(tester, 'Live location ended');

    expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Copy'), findsNothing);
  });

  group('reactions', () {
    testWidgets('a quick reaction is sent', (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tester.tap(find.text('👍'));
      await harness.settle(tester);

      final reaction = requestsTo('/send/m.reaction/').single;
      final relates = (jsonDecode(reaction.body) as Map)['m.relates_to'] as Map;
      expect((relates['event_id'], relates['key']), (r'$m1', '👍'));
    });

    testWidgets('a refused reaction says so', (tester) async {
      refuse = true;
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tester.tap(find.text('❤️'));
      await harness.settle(tester);

      expect(find.text('Reaction not sent. Try again.'), findsOneWidget);
    });

    testWidgets('a reaction picked from the full picker is sent', (
      tester,
    ) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tester.tap(find.byTooltip('More reactions'));
      await harness.settle(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Tab),
            )
            .at(1),
      );
      await harness.settle(tester);
      final emoji = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('😀'),
      );
      await tester.tap(emoji.first);
      await harness.settle(tester);

      final reaction = requestsTo('/send/m.reaction/').single;
      final relates = (jsonDecode(reaction.body) as Map)['m.relates_to'] as Map;
      expect(relates['key'], '😀');
    });

    testWidgets('More reactions opens the full picker', (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tester.tap(find.byTooltip('More reactions'));
      await harness.settle(tester);

      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await harness.settle(tester);

      expect(requestsTo('/send/m.reaction/'), isEmpty);
    });
  });

  group('the facts shown', () {
    void seenByBobAt(DateTime at) =>
        harness.room.receiptState = LatestReceiptState(
          global: LatestReceiptStateForTimeline(
            ownPrivate: null,
            ownPublic: null,
            latestOwnReceipt: null,
            otherUsers: {
              '@bob:example.org': LatestReceiptStateData(
                r'$mine',
                at.millisecondsSinceEpoch,
              ),
            },
          ),
        );

    testWidgets('your own message says it has not been seen', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'anyone?')]);

      await openActions(tester, 'anyone?');

      expect(find.text('Not seen yet'), findsOneWidget);
      expect(find.textContaining('Sent 2026-09-20 12:05'), findsOneWidget);
    });

    testWidgets('and later who saw it and when', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'anyone?')]);
      seenByBobAt(DateTime(2026, 9, 20, 12, 7));

      await openActions(tester, 'anyone?');

      expect(find.text('Seen by Bob · 2026-09-20 12:07'), findsOneWidget);
    });

    testWidgets('the seen line updates while the sheet is open', (
      tester,
    ) async {
      await openRoom(tester, () => [own(r'$mine', 'anyone?')]);

      await openActions(tester, 'anyone?');
      expect(find.text('Not seen yet'), findsOneWidget);

      seenByBobAt(DateTime(2026, 9, 20, 12, 9));
      harness.client.onSync.add(SyncUpdate(nextBatch: 'next'));
      await harness.settle(tester);

      expect(find.text('Seen by Bob · 2026-09-20 12:09'), findsOneWidget);
    });

    testWidgets('an attachment gives its file details', (tester) async {
      await openRoom(
        tester,
        () => [
          buildTestEvent(
            harness.room,
            eventId: r'$pdf',
            senderId: '@bob:example.org',
            originServerTs: DateTime(2026, 9, 20, 12),
            status: EventStatus.synced,
            content: {
              'msgtype': 'm.file',
              'body': 'plan.pdf',
              'url': 'mxc://example.org/pdf',
              'info': {'size': 2048},
            },
          ),
        ],
      );

      await openActions(tester, 'plan');

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('2.0 KB'),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(ListTile, 'Save'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Copy'), findsNothing);
    });
  });

  group('saving and sharing attachments', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('zuno_save_');
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => temp.path,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(pathProvider, null);
        temp.deleteSync(recursive: true);
      });
    });

    Event photo(String id, {int? index}) => buildTestEvent(
      harness.room,
      eventId: id,
      senderId: '@bob:example.org',
      originServerTs: DateTime(2026, 9, 20, 12),
      status: EventStatus.synced,
      content: {
        'msgtype': 'm.image',
        'body': '$id.jpg',
        'url': 'mxc://example.org/$id',
        'info': {'w': 40, 'h': 30, 'mimetype': 'image/jpeg'},
        if (index != null)
          ...galleryGroupContent(id: 'g', index: index, count: 2),
      },
    );

    Future<void> openPhotoActions(WidgetTester tester) async {
      await tester.longPress(
        find
            .byWidgetPredicate((w) => w is ImageMessage || w is GalleryMessage)
            .first,
      );
      await harness.settle(tester);
    }

    testWidgets('a photo that cannot be fetched is not saved, and says so', (
      tester,
    ) async {
      await openRoom(tester, () => [photo('p1')]);

      await openPhotoActions(tester);
      await tapAction(tester, 'Save');
      await harness.drive(tester, turns: 8);

      expect(find.text('Could not save. Try again.'), findsOneWidget);
    });

    testWidgets('a photo that cannot be fetched is not shared, and says so', (
      tester,
    ) async {
      await openRoom(tester, () => [photo('p1')]);

      await openPhotoActions(tester);
      await tapAction(tester, 'Share');
      await harness.drive(tester, turns: 8);

      expect(find.text('Could not share. Try again.'), findsOneWidget);
    });

    testWidgets('a gallery offers to save all of it and counts the result', (
      tester,
    ) async {
      await openRoom(
        tester,
        () => [photo('p2', index: 1), photo('p1', index: 0)],
      );

      await openPhotoActions(tester);
      expect(find.widgetWithText(ListTile, 'Save all (2)'), findsOneWidget);
      await tapAction(tester, 'Save all (2)');
      await harness.drive(tester, turns: 8);

      expect(find.text('Could not save'), findsOneWidget);
    });
  });
}
