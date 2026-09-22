import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/mxc_avatar.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/data/message_row_data.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';
import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/not_sent.dart';
import 'package:zuno/features/chat/presentation/reply_target_cache.dart';
import 'package:zuno/features/chat/presentation/swipe_to_reply.dart';

import '../../../helpers/fake_matrix.dart';

const me = '@me:example.org';
const bob = '@bob:example.org';

void main() {
  late Client client;
  late Room room;
  late StoredEventsFakeDatabaseApi db;
  late int lookups;
  final resent = <Event>[];
  final noon = DateTime(2026, 9, 20, 12);

  setUp(() {
    db = StoredEventsFakeDatabaseApi();
    client = buildTestClient(userId: me, database: db);
    room = buildTestRoom(client)..partial = false;
    room.setState(
      User(bob, membership: 'join', displayName: 'Bob', room: room),
    );
    room.setState(User(me, membership: 'join', displayName: 'Me', room: room));
    lookups = 0;
    resent.clear();
  });

  Event text(
    String id, {
    String sender = bob,
    String body = 'hello',
    EventStatus status = EventStatus.synced,
    Map<String, Object?> extra = const {},
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: sender,
    originServerTs: noon,
    status: status,
    content: {'msgtype': 'm.text', 'body': body, ...extra},
  );

  Future<void> pumpTile(
    WidgetTester tester,
    Event event, {
    List<Event>? events,
    Event? older,
    bool canReply = true,
    ReplyTargetCache? cache,
  }) async {
    final all = events ?? [event];
    db.events = all;
    final timeline = (await tester.runAsync(room.getTimeline))!;
    addTearDown(timeline.cancelSubscriptions);
    final index = {for (final e in all) e.eventId: e};
    final record = messageRowDataFor(
      event: event,
      timeline: timeline,
      index: index,
      older: older,
      newer: null,
      isLastOwn: false,
      gallery: null,
      galleryFailureIndexes: const [],
      canReply: canReply,
      linkPreviews: false,
      now: noon,
      use24Hour: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: zunoLightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageTile(
                data: record,
                event: event,
                timeline: timeline,
                replyTarget: index[record.replyToId],
                replyTargets:
                    cache ??
                    ReplyTargetCache((id) async {
                      lookups++;
                      return null;
                    }),
                pendingSend: ValueNotifier<PendingAttachmentSend?>(null),
                gallery: null,
                galleryFailures: const [],
                onLongPress: () {},
                onSwipeReply: canReply ? () {} : null,
                onResend: resent.add,
                onRetryFailedSend: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Material bubbleMaterial(WidgetTester tester) => tester.widget<Material>(
    find
        .descendant(
          of: find.byType(MessageBubble),
          matching: find.byType(Material),
        )
        .first,
  );

  testWidgets('a tile holds no Opacity and no Dismissible', (tester) async {
    final hidden = buildTestEvent(
      room,
      eventId: r'$s',
      senderId: bob,
      type: EventTypes.RoomName,
      stateKey: '',
      originServerTs: noon,
      content: {'name': 'x'},
    );
    for (final event in [
      text(r'$a', sender: me, status: EventStatus.sending),
      text(r'$b', sender: me, status: EventStatus.sent),
      text(r'$c'),
      hidden,
    ]) {
      await pumpTile(tester, event);
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
    }
  });

  testWidgets('a sending message shows the clock at full color', (
    tester,
  ) async {
    await pumpTile(
      tester,
      text(r'$a', sender: me, status: EventStatus.sending),
    );
    expect(find.byIcon(Icons.schedule), findsWidgets);
    expect(bubbleMaterial(tester).color, ZunoColors.light.bubbleOutgoing);
  });

  testWidgets('a failed message shows Not sent and resends on tap', (
    tester,
  ) async {
    final failed = text(r'$a', sender: me, status: EventStatus.error);
    await pumpTile(tester, failed);
    expect(find.byType(NotSentRow), findsOneWidget);
    expect(find.text('12:00'), findsNothing);

    await tester.tap(find.text('hello'));
    expect(resent, [failed]);
  });

  testWidgets(
    'the name and avatar show only on the first message of a run in a room',
    (tester) async {
      await pumpTile(tester, text(r'$a'));
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byType(MxcAvatar), findsOneWidget);

      await pumpTile(tester, text(r'$b'), older: text(r'$a'));
      expect(find.text('Bob'), findsNothing);
      expect(find.byType(MxcAvatar), findsNothing);

      await pumpTile(tester, text(r'$c', sender: me));
      expect(find.text('Me'), findsNothing);
      expect(find.byType(MxcAvatar), findsNothing);
    },
  );

  testWidgets('a direct chat shows neither name nor avatar', (tester) async {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        bob: [room.id],
      },
    );
    await pumpTile(tester, text(r'$a'));
    expect(find.text('Bob'), findsNothing);
    expect(find.byType(MxcAvatar), findsNothing);
  });

  testWidgets(
    'no swipe when replying is not allowed, deleted or undecryptable',
    (tester) async {
      await pumpTile(tester, text(r'$a'));
      expect(find.byType(SwipeToReply), findsOneWidget);

      await pumpTile(tester, text(r'$a'), canReply: false);
      expect(find.byType(SwipeToReply), findsNothing);

      final deleted = text(r'$b')
        ..setRedactionEvent(
          buildTestEvent(
            room,
            eventId: r'$r',
            senderId: bob,
            type: EventTypes.Redaction,
            originServerTs: noon,
          ),
        );
      await pumpTile(tester, deleted);
      expect(find.byType(SwipeToReply), findsNothing);
      expect(find.text('Message deleted'), findsOneWidget);

      final undecryptable = buildTestEvent(
        room,
        eventId: r'$c',
        senderId: bob,
        type: EventTypes.Encrypted,
        originServerTs: noon,
        content: {'msgtype': MessageTypes.BadEncrypted, 'body': 'x'},
      );
      await pumpTile(tester, undecryptable);
      expect(find.byType(SwipeToReply), findsNothing);
    },
  );

  testWidgets('a text bubble has no IntrinsicWidth; one with a quote has', (
    tester,
  ) async {
    await pumpTile(tester, text(r'$a'));
    expect(find.byType(IntrinsicWidth), findsNothing);

    final target = text(r'$t', body: 'the original');
    final reply = text(
      r'$b',
      extra: {
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$t'},
        },
      },
    );
    await pumpTile(tester, reply, events: [reply, target]);
    expect(find.byType(IntrinsicWidth), findsOneWidget);
    expect(find.text('the original'), findsOneWidget);
    expect(lookups, 0);
  });

  testWidgets('a short message is not forced to a third of the screen', (
    tester,
  ) async {
    await pumpTile(tester, text(r'$a', sender: me, body: 'ok'));
    final width = tester.getSize(find.byType(MessageBubble)).width;
    expect(width, lessThan(800 / 3));
  });

  testWidgets('plain text tucks the meta; formatted text keeps its own row', (
    tester,
  ) async {
    await pumpTile(tester, text(r'$a'));
    expect(find.byType(TuckedMeta), findsOneWidget);

    await pumpTile(
      tester,
      text(
        r'$b',
        body: 'hi there',
        extra: {
          'format': 'org.matrix.custom.html',
          'formatted_body': 'hi <em>there</em>',
        },
      ),
    );
    expect(find.byType(Html), findsOneWidget);
    expect(find.byType(TuckedMeta), findsNothing);
    expect(find.byType(MessageMeta), findsOneWidget);
  });

  testWidgets('a missing reply target is looked up once across rebuilds', (
    tester,
  ) async {
    final reply = text(
      r'$b',
      extra: {
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$gone'},
        },
      },
    );
    final cache = ReplyTargetCache((id) async {
      lookups++;
      return null;
    });
    await pumpTile(tester, reply, cache: cache);
    await pumpTile(tester, reply, cache: cache);
    await pumpTile(tester, reply, cache: cache);
    expect(find.text('Original message not available'), findsOneWidget);
    expect(lookups, 1);
  });

  testWidgets('a long message collapses with the time beside Read more', (
    tester,
  ) async {
    await pumpTile(tester, text(r'$a', body: 'long words ' * 80));
    expect(find.text('Read more'), findsOneWidget);
    expect(find.byType(TuckedMeta), findsNothing);
    expect(find.byType(MessageMeta), findsOneWidget);
    expect(
      tester.getCenter(find.byType(MessageMeta)).dy,
      closeTo(tester.getCenter(find.text('Read more')).dy, 6),
    );

    await tester.tap(find.text('Read more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
    expect(find.byType(TuckedMeta), findsOneWidget);
  });

  testWidgets('a captioned photo tucks the time into the caption', (
    tester,
  ) async {
    final photo = buildTestEvent(
      room,
      eventId: r'$p',
      senderId: bob,
      originServerTs: noon,
      status: EventStatus.synced,
      content: {
        'msgtype': 'm.image',
        'body': 'IMG_1.jpg',
        'filename': 'IMG_1.jpg',
        'url': 'mxc://example.org/abc',
        'info': {'w': 400, 'h': 300, 'mimetype': 'image/jpeg'},
      },
    );
    await pumpTile(tester, photo);
    expect(find.byType(TuckedMeta), findsNothing);
    expect(
      tester.widget<MessageMeta>(find.byType(MessageMeta)).onMedia,
      isTrue,
    );

    final captioned = buildTestEvent(
      room,
      eventId: r'$q',
      senderId: bob,
      originServerTs: noon,
      status: EventStatus.synced,
      content: {
        'msgtype': 'm.image',
        'body': 'The new boiler',
        'filename': 'IMG_2.jpg',
        'url': 'mxc://example.org/def',
        'info': {'w': 400, 'h': 300, 'mimetype': 'image/jpeg'},
      },
    );
    await pumpTile(tester, captioned);
    expect(find.byType(TuckedMeta), findsOneWidget);
    expect(
      find.textContaining('The new boiler', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('deleted and undecryptable messages cannot be held', (
    tester,
  ) async {
    InkWell ink() => tester.widget<InkWell>(
      find.descendant(
        of: find.byType(MessageBubble),
        matching: find.byType(InkWell),
      ),
    );
    await pumpTile(tester, text(r'$a'));
    expect(ink().onLongPress, isNotNull);

    final deleted = text(r'$b')
      ..setRedactionEvent(
        buildTestEvent(
          room,
          eventId: r'$r',
          senderId: bob,
          type: EventTypes.Redaction,
          originServerTs: noon,
        ),
      );
    await pumpTile(tester, deleted);
    expect(ink().onLongPress, isNull);

    await pumpTile(
      tester,
      buildTestEvent(
        room,
        eventId: r'$c',
        senderId: bob,
        type: EventTypes.Encrypted,
        originServerTs: noon,
        content: {'msgtype': MessageTypes.BadEncrypted, 'body': 'x'},
      ),
    );
    expect(ink().onLongPress, isNull);
  });

  testWidgets('a short formatted message keeps a width floor', (tester) async {
    await pumpTile(
      tester,
      text(
        r'$a',
        body: '- item',
        extra: {
          'format': 'org.matrix.custom.html',
          'formatted_body': '<ul><li>item</li></ul>',
        },
      ),
    );
    expect(
      tester.getSize(find.byType(Html)).width,
      greaterThanOrEqualTo(800 / 3 - 24),
    );
  });

  testWidgets('a failed short message stays as small as its text', (
    tester,
  ) async {
    await pumpTile(
      tester,
      text(r'$a', sender: me, body: 'ok', status: EventStatus.error),
    );
    expect(tester.getSize(find.byType(MessageBubble)).width, lessThan(400));
  });

  testWidgets('a file bubble takes the fixed media width', (tester) async {
    await pumpTile(
      tester,
      buildTestEvent(
        room,
        eventId: r'$f',
        senderId: bob,
        originServerTs: noon,
        status: EventStatus.synced,
        content: {
          'msgtype': 'm.file',
          'body': 'a.pdf',
          'info': {'size': 1024},
        },
      ),
    );
    expect(
      tester.getSize(find.byType(MessageBubble)).width,
      closeTo(800 * 2 / 3, 0.5),
    );
  });
}
