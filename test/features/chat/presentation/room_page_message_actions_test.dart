import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';
import 'package:zuno/features/chat/presentation/message_contents/file_message.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';
import 'package:zuno/features/chat/presentation/not_sent.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/pump_until.dart';
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

  Event own(
    String id,
    String body, {
    EventStatus status = EventStatus.synced,
  }) => buildTestEvent(
    harness.room,
    eventId: id,
    senderId: '@me:example.org',
    originServerTs: DateTime(2026, 9, 20, 12, 5),
    status: status,
    content: {'msgtype': 'm.text', 'body': body},
  );

  Future<void> openRoom(
    WidgetTester tester,
    List<Event> Function() events, {
    List<Override> overrides = const [],
    bool canPost = true,
    bool encrypted = false,
  }) async {
    harness = RoomPageHarness(
      db: SendingFakeDatabaseApi(),
      overrides: overrides,
    );
    if (!canPost) harness.blockPosting();
    if (encrypted) encryptRoom(harness.room);
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

  Future<void> doubleTap(WidgetTester tester, String body) async {
    final message = find.ancestor(
      of: find.textContaining(body, findRichText: true).first,
      matching: find.byType(MessageBubble),
    );
    await tester.tap(message);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(message);
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

  String composerText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

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

    testWidgets('dropping it keeps what you typed', (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tapAction(tester, 'Reply');
      await tester.enterText(find.byType(TextField), 'on second thought');
      await tester.pump();
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();

      expect(find.text('Replying to Bob'), findsNothing);
      expect(composerText(tester), 'on second thought');
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

    testWidgets('what you were typing comes back when the edit is cancelled', (
      tester,
    ) async {
      await openRoom(tester, () => [own(r'$mine', 'teh plan')]);
      await tester.enterText(find.byType(TextField), 'a long draft');
      await tester.pump();

      await openActions(tester, 'teh plan');
      await tapAction(tester, 'Edit');
      expect(composerText(tester), 'teh plan');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();

      expect(composerText(tester), 'a long draft');
      expect(harness.sent, isEmpty);
    });

    testWidgets('what you were typing comes back once the edit is sent', (
      tester,
    ) async {
      await openRoom(tester, () => [own(r'$mine', 'teh plan')]);
      await tester.enterText(find.byType(TextField), 'a long draft');
      await tester.pump();

      await openActions(tester, 'teh plan');
      await tapAction(tester, 'Edit');
      await sendTyped(tester, 'the plan');

      expect(
        (harness.sent.single['m.new_content']! as Map)['body'],
        'the plan',
      );
      expect(composerText(tester), 'a long draft');
      expect(find.text('Editing message'), findsNothing);
    });

    testWidgets('replying instead of editing brings back the draft, not the '
        'edit', (tester) async {
      await openRoom(
        tester,
        () => [own(r'$mine', 'teh plan'), harness.message(r'$m1')],
      );
      await tester.enterText(find.byType(TextField), 'a long draft');
      await tester.pump();

      await openActions(tester, 'teh plan');
      await tapAction(tester, 'Edit');
      await openActions(tester, 'hello');
      await tapAction(tester, 'Reply');

      expect(find.text('Replying to Bob'), findsOneWidget);
      expect(composerText(tester), 'a long draft');
    });

    testWidgets("someone else's message cannot be edited", (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');

      expect(find.widgetWithText(ListTile, 'Edit'), findsNothing);
    });

    group('that failed', () {
      late StreamController<ConnectionStatus> status;

      Event failedEdit(String id, String body, {required int minute}) =>
          buildTestEvent(
            harness.room,
            eventId: id,
            senderId: '@me:example.org',
            originServerTs: DateTime(2026, 9, 20, 12, minute),
            status: EventStatus.error,
            content: {
              'msgtype': 'm.text',
              'body': '* $body',
              'm.new_content': {'msgtype': 'm.text', 'body': body},
              'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$mine'},
            },
          );

      Future<void> openWithFailedEdit(WidgetTester tester) async {
        status = StreamController<ConnectionStatus>.broadcast();
        addTearDown(status.close);
        await openRoom(
          tester,
          () => [
            failedEdit('txn-edit', 'the plan', minute: 6),
            own(r'$mine', 'teh plan'),
          ],
          overrides: [
            connectionStatusProvider.overrideWith((ref) => status.stream),
          ],
        );
        status.add(ConnectionStatus.noInternet);
        await harness.drive(tester, turns: 2);
      }

      Future<void> comeBackOnline(WidgetTester tester) async {
        status.add(ConnectionStatus.online);
        await harness.drive(tester, turns: 4);
      }

      testWidgets('says so, and a tap sends it again as an edit', (
        tester,
      ) async {
        await openWithFailedEdit(tester);

        expect(find.byType(NotSentRow), findsOneWidget);
        await tester.tap(find.text('the plan'));
        await harness.settle(tester);

        final sent = harness.sent.single;
        expect((sent['m.new_content']! as Map)['body'], 'the plan');
        expect((sent['m.relates_to']! as Map)['event_id'], r'$mine');
      });

      testWidgets('goes again as an edit once back online', (tester) async {
        await openWithFailedEdit(tester);

        await comeBackOnline(tester);

        final sent = harness.sent.single;
        expect((sent['m.new_content']! as Map)['body'], 'the plan');
        expect((sent['m.relates_to']! as Map)['rel_type'], 'm.replace');
      });

      testWidgets('never goes again once a newer edit replaced it', (
        tester,
      ) async {
        await openWithFailedEdit(tester);

        await openActions(tester, 'the plan');
        await tapAction(tester, 'Edit');
        await sendTyped(tester, 'the real plan');
        await comeBackOnline(tester);

        expect(
          [for (final s in harness.sent) (s['m.new_content']! as Map)['body']],
          ['the real plan'],
        );
      });

      testWidgets('never goes again once its message is deleted', (
        tester,
      ) async {
        await openWithFailedEdit(tester);

        await openActions(tester, 'the plan');
        await tapAction(tester, 'Delete');
        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await harness.settle(tester);
        harness.client.onTimelineEvent.add(
          buildTestEvent(
            harness.room,
            eventId: r'$redaction',
            senderId: '@me:example.org',
            type: EventTypes.Redaction,
            originServerTs: DateTime(2026, 9, 20, 12, 7),
            content: {'redacts': r'$mine'},
          )..redacts = r'$mine',
        );
        await harness.settle(tester);
        await comeBackOnline(tester);

        expect(requestsTo('/redact/'), hasLength(1));
        expect(harness.sent, isEmpty);
      });
    });
  });

  group('a message not sent yet', () {
    testWidgets('offers no reactions, Reply, Edit or Delete while on its way', (
      tester,
    ) async {
      await openRoom(
        tester,
        () => [own('txn-1', 'on its way', status: EventStatus.sending)],
      );

      await openActions(tester, 'on its way');

      expect(find.text('👍'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Reply'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Edit'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Delete'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Copy'), findsOneWidget);
    });

    testWidgets('an attachment still on its way offers Delete, which drops '
        'it', (tester) async {
      await openRoom(
        tester,
        () => [
          buildTestEvent(
            harness.room,
            eventId: 'txn-1',
            senderId: '@me:example.org',
            originServerTs: DateTime(2026, 9, 20, 12, 5),
            status: EventStatus.sending,
            content: {
              'msgtype': 'm.file',
              'body': 'plan.pdf',
              'filename': 'plan.pdf',
              'info': {'size': 3, 'mimetype': 'application/pdf'},
            },
          ),
        ],
      );

      await tester.longPress(find.byType(FileMessage));
      await harness.settle(tester);
      await tapAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await harness.settle(tester);

      expect(find.byType(FileMessage), findsNothing);
      expect(
        harness.requests.where((path) => path.contains('/redact/')),
        isEmpty,
      );
    });

    testWidgets('a failed one offers no reactions, Reply or Edit', (
      tester,
    ) async {
      await openRoom(
        tester,
        () => [own('txn-1', 'stuck', status: EventStatus.error)],
      );

      await openActions(tester, 'stuck');

      expect(find.text('👍'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Reply'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Edit'), findsNothing);
    });

    testWidgets('the sheet says it was not sent, or is still sending, never '
        'a sent time', (tester) async {
      await openRoom(
        tester,
        () => [
          own('txn-1', 'stuck', status: EventStatus.error),
          own('txn-2', 'on its way', status: EventStatus.sending),
        ],
      );

      await openActions(tester, 'stuck');
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.textContaining('Sent '), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await harness.settle(tester);

      await openActions(tester, 'on its way');
      expect(find.text('Sending…'), findsOneWidget);
      expect(find.textContaining('Sent '), findsNothing);
    });

    testWidgets('a failed one is deleted from this device only', (
      tester,
    ) async {
      await openRoom(
        tester,
        () => [
          own('txn-1', 'stuck', status: EventStatus.error),
          harness.message(r'$m1'),
        ],
      );

      await openActions(tester, 'stuck');
      await tapAction(tester, 'Delete');
      expect(
        find.text(
          'It was not sent, so only this device has it. Nobody can '
          'undo this.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await harness.settle(tester);

      expect(requestsTo('/redact/'), isEmpty);
      expect(find.text('stuck'), findsNothing);
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
      final now = clock.now();
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

    group('a gallery', () {
      Event ownPhoto(String id, int index) => buildTestEvent(
        harness.room,
        eventId: id,
        senderId: '@me:example.org',
        originServerTs: DateTime(2026, 9, 20, 12, 5),
        status: EventStatus.synced,
        content: {
          'msgtype': 'm.image',
          'body': 'photo.jpg',
          'url': 'mxc://example.org/${id.substring(1)}',
          'info': {'w': 40, 'h': 30, 'mimetype': 'image/jpeg'},
          ...galleryGroupContent(id: 'g', index: index, count: 3),
        },
      );

      Future<void> deleteGallery(WidgetTester tester) async {
        await openRoom(
          tester,
          () => [ownPhoto(r'$p3', 2), ownPhoto(r'$p2', 1), ownPhoto(r'$p1', 0)],
        );
        await tester.longPress(find.byType(GalleryMessage));
        await harness.settle(tester);
        await tapAction(tester, 'Delete all (3)');
        expect(find.text('Delete 3 items?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Delete all'));
        await harness.settle(tester);
      }

      testWidgets('is deleted whole, not just its newest item', (tester) async {
        await deleteGallery(tester);

        final redacted = [
          for (final request in requestsTo('/redact/'))
            Uri.decodeComponent(request.url.pathSegments.reversed.elementAt(1)),
        ];
        expect(redacted, unorderedEquals([r'$p1', r'$p2', r'$p3']));
      });

      testWidgets('a refusal says not everything was deleted', (tester) async {
        refuse = true;

        await deleteGallery(tester);

        expect(find.text('Some items not deleted. Try again.'), findsOneWidget);
      });
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
    final now = clock.now();
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

    testWidgets('closing the full picker reacts with nothing', (tester) async {
      await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

      await openActions(tester, 'hello');
      await tester.tap(find.byTooltip('More reactions'));
      await harness.settle(tester);

      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await harness.settle(tester);

      expect(requestsTo('/send/m.reaction/'), isEmpty);
    });

    group('double-tapping a message', () {
      Event myHeartOn(String eventId) => buildTestEvent(
        harness.room,
        eventId: r'$heart',
        senderId: '@me:example.org',
        originServerTs: DateTime(2026, 9, 20, 12, 1),
        status: EventStatus.synced,
        type: EventTypes.Reaction,
        content: {
          'm.relates_to': {
            'rel_type': RelationshipTypes.reaction,
            'event_id': eventId,
            'key': '❤️',
          },
        },
      );

      testWidgets('reacts with a heart', (tester) async {
        await openRoom(tester, () => [harness.message(r'$m1', body: 'hello')]);

        await doubleTap(tester, 'hello');

        final reaction = requestsTo('/send/m.reaction/').single;
        final relates =
            (jsonDecode(reaction.body) as Map)['m.relates_to'] as Map;
        expect((relates['event_id'], relates['key']), (r'$m1', '❤️'));
      });

      testWidgets('takes my heart back off', (tester) async {
        await openRoom(
          tester,
          () => [myHeartOn(r'$m1'), harness.message(r'$m1', body: 'hello')],
        );

        await doubleTap(tester, 'hello');

        expect(
          requestsTo('/redact/').single.url.path,
          contains(Uri.encodeComponent(r'$heart')),
        );
        expect(requestsTo('/send/m.reaction/'), isEmpty);
      });

      testWidgets('does nothing while the message is on its way', (
        tester,
      ) async {
        await openRoom(
          tester,
          () => [own('txn-1', 'on its way', status: EventStatus.sending)],
        );

        await doubleTap(tester, 'on its way');

        expect(requestsTo('/send/m.reaction/'), isEmpty);
      });

      testWidgets('does nothing in a room you cannot post in', (tester) async {
        await openRoom(
          tester,
          () => [harness.message(r'$m1', body: 'hello')],
          canPost: false,
        );

        await doubleTap(tester, 'hello');

        expect(requestsTo('/send/m.reaction/'), isEmpty);
      });

      testWidgets('does nothing on a deleted message', (tester) async {
        await openRoom(
          tester,
          () => [
            harness.message(r'$m1', body: 'hello')
              ..unsigned = {
                'redacted_because': {
                  'event_id': r'$redaction',
                  'type': EventTypes.Redaction,
                  'sender': '@bob:example.org',
                  'content': {},
                  'origin_server_ts': 0,
                },
              },
          ],
        );

        await doubleTap(tester, 'Message deleted');

        expect(requestsTo('/send/m.reaction/'), isEmpty);
      });
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
      expect(
        find.textContaining('Sent Sep 20, 2026 at 12:05\u202fPM'),
        findsOneWidget,
      );
    });

    testWidgets('and later who saw it and when', (tester) async {
      await openRoom(tester, () => [own(r'$mine', 'anyone?')]);
      seenByBobAt(DateTime(2026, 9, 20, 12, 7));

      await openActions(tester, 'anyone?');

      expect(
        find.text('Seen by Bob · Sep 20, 2026 at 12:07\u202fPM'),
        findsOneWidget,
      );
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

      expect(
        find.text('Seen by Bob · Sep 20, 2026 at 12:09\u202fPM'),
        findsOneWidget,
      );
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

  group('in an encrypted chat', () {
    Event fromBob({required bool encrypted}) => buildTestEvent(
      harness.room,
      eventId: r'$bob',
      senderId: '@bob:example.org',
      originServerTs: DateTime(2026, 9, 20, 12),
      status: EventStatus.synced,
      encrypted: encrypted,
      content: {'msgtype': 'm.text', 'body': 'meet at the usual place'},
    );

    Finder bubbleLock() => find.bySemanticsLabel(RegExp('Not encrypted'));

    testWidgets('a message sent without encryption shows a lock and says so '
        'on its sheet', (tester) async {
      await openRoom(
        tester,
        () => [fromBob(encrypted: false)],
        encrypted: true,
      );

      expect(bubbleLock(), findsOneWidget);

      await openActions(tester, 'usual place');

      expect(
        find.text('This message is not encrypted, so the server can read it.'),
        findsOneWidget,
      );
    });

    testWidgets('an encrypted message shows neither', (tester) async {
      await openRoom(tester, () => [fromBob(encrypted: true)], encrypted: true);

      expect(bubbleLock(), findsNothing);

      await openActions(tester, 'usual place');

      expect(find.textContaining('not encrypted'), findsNothing);
    });

    group('the badge', () {
      Rect bubbleOf(WidgetTester tester, String body) => tester.getRect(
        find.ancestor(
          of: find.textContaining(body, findRichText: true),
          matching: find.byType(MessageBubble),
        ),
      );

      Rect badge(WidgetTester tester) => tester.getRect(
        find
            .ancestor(
              of: find.byIcon(notEncryptedIcon),
              matching: find.byType(Container),
            )
            .first,
      );

      testWidgets('straddles the top corner facing the middle of the '
          'screen', (tester) async {
        await openRoom(
          tester,
          () => [fromBob(encrypted: false)],
          encrypted: true,
        );
        final bubble = bubbleOf(tester, 'usual place');

        expect(badge(tester).center.dx, closeTo(bubble.right, 0.5));
        expect(badge(tester).top, closeTo(bubble.top, 0.5));
      });

      testWidgets('on your own message straddles its left corner', (
        tester,
      ) async {
        await openRoom(
          tester,
          () => [own(r'$mine', 'sent from elsewhere')],
          encrypted: true,
        );
        final bubble = bubbleOf(tester, 'sent from elsewhere');

        expect(badge(tester).center.dx, closeTo(bubble.left, 0.5));
        expect(badge(tester).top, closeTo(bubble.top, 0.5));
      });

      testWidgets('never covers the text, even on a full-width bubble', (
        tester,
      ) async {
        const long =
            'and bring the keys, the spare set is in the drawer by the door '
            'next to the coats, the one with the broken handle';
        await openRoom(
          tester,
          () => [
            buildTestEvent(
              harness.room,
              eventId: r'$long',
              senderId: '@bob:example.org',
              originServerTs: DateTime(2026, 9, 20, 12),
              status: EventStatus.synced,
              content: {'msgtype': 'm.text', 'body': long},
            ),
          ],
          encrypted: true,
        );
        final text = tester.getRect(
          find.textContaining('spare set', findRichText: true).first,
        );

        expect(badge(tester).left, greaterThanOrEqualTo(text.right));
      });

      testWidgets('moves nothing around it', (tester) async {
        Event bob(String id, String body, int minute, {required bool plain}) =>
            buildTestEvent(
              harness.room,
              eventId: id,
              senderId: '@bob:example.org',
              originServerTs: DateTime(2026, 9, 20, 12, minute),
              status: EventStatus.synced,
              encrypted: !plain,
              content: {'msgtype': 'm.text', 'body': body},
            );
        await openRoom(
          tester,
          () => [
            bob(r'$c', 'third', 2, plain: false),
            bob(r'$b', 'second', 1, plain: true),
            bob(r'$a', 'first', 0, plain: false),
          ],
          encrypted: true,
        );
        final first = bubbleOf(tester, 'first');
        final second = bubbleOf(tester, 'second');
        final third = bubbleOf(tester, 'third');

        expect(second.top - first.bottom, third.top - second.bottom);
      });

      testWidgets('leaves the time row', (tester) async {
        await openRoom(
          tester,
          () => [fromBob(encrypted: false)],
          encrypted: true,
        );

        expect(
          find.descendant(
            of: find.byType(MessageMeta),
            matching: find.byIcon(notEncryptedIcon),
          ),
          findsNothing,
        );
      });
    });

    group('a photo', () {
      Event photoFromBob(String id, {required bool encrypted, int? index}) =>
          buildTestEvent(
            harness.room,
            eventId: id,
            senderId: '@bob:example.org',
            originServerTs: DateTime(2026, 9, 20, 12),
            status: EventStatus.synced,
            encrypted: encrypted,
            content: {
              'msgtype': 'm.image',
              'body': '$id.jpg',
              'url': 'mxc://example.org/${id.substring(1)}',
              'info': {'w': 40, 'h': 30, 'mimetype': 'image/jpeg'},
              if (index != null)
                ...galleryGroupContent(id: 'g', index: index, count: 2),
            },
          );

      testWidgets('sent without encryption shows the lock badge', (
        tester,
      ) async {
        await openRoom(
          tester,
          () => [photoFromBob(r'$p', encrypted: false)],
          encrypted: true,
        );

        expect(bubbleLock(), findsOneWidget);
      });

      testWidgets('that was encrypted shows no lock', (tester) async {
        await openRoom(
          tester,
          () => [photoFromBob(r'$p', encrypted: true)],
          encrypted: true,
        );

        expect(bubbleLock(), findsNothing);
      });

      testWidgets('in a gallery marks the gallery once', (tester) async {
        await openRoom(
          tester,
          () => [
            photoFromBob(r'$p2', encrypted: false, index: 1),
            photoFromBob(r'$p1', encrypted: true, index: 0),
          ],
          encrypted: true,
        );

        expect(find.byType(GalleryMessage), findsOneWidget);
        expect(bubbleLock(), findsOneWidget);
      });
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
      await pumpUntil(
        tester,
        () => shows('Could not save. Try again.'),
        reason: 'the failed save to be reported',
      );

      expect(find.text('Could not save. Try again.'), findsOneWidget);
    });

    testWidgets('a photo that cannot be fetched is not shared, and says so', (
      tester,
    ) async {
      await openRoom(tester, () => [photo('p1')]);

      await openPhotoActions(tester);
      await tapAction(tester, 'Share');
      await pumpUntil(
        tester,
        () => shows('Could not share. Try again.'),
        reason: 'the failed share to be reported',
      );

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
      await pumpUntil(
        tester,
        () => shows('Could not save'),
        reason: 'the failed gallery save to be counted',
      );

      expect(find.text('Could not save'), findsOneWidget);
    });
  });
}
