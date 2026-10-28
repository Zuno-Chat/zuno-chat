import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_sharing.dart';
import 'package:zuno/core/location/live_location_viewing.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/matrix/forwarded_message.dart';
import 'package:zuno/core/matrix/linkified_text.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/matrix/mxc_avatar.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/data/message_row_data.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';
import 'package:zuno/features/chat/presentation/forward_icon.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';
import 'package:zuno/features/chat/presentation/message_contents/media_message.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';
import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/not_sent.dart';
import 'package:zuno/features/chat/presentation/reply_target_cache.dart';
import 'package:zuno/features/chat/presentation/swipe_to_reply.dart';
import 'package:zuno/features/location/presentation/live_location_map_page.dart';

import '../../../helpers/date_labels.dart';
import '../../../helpers/fake_live_location.dart';
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
    List<Event>? gallery,
    bool canRespond = true,
    List<Override> overrides = const [],
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
      gallery: gallery,
      galleryFailureIndexes: const [],
      canRespond: canRespond,
      now: noon,
      labels: testDateLabels(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: zunoLightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageTile(
                data: record,
                event: event,
                timeline: timeline,
                replyTarget: index[record.replyToId],
                replyTargets: ReplyTargetCache((id) async {
                  lookups++;
                  return null;
                }),
                pendingSend: ValueNotifier<PendingAttachmentSend?>(null),
                gallery: gallery,
                galleryFailures: const [],
                onLongPress: () {},
                onDoubleTap: record.canRespond ? () {} : null,
                onSwipeReply: record.canRespond ? () {} : null,
                onResend: resent.add,
                onRetryFailedSend: (_) {},
                onOpenMedia: (_) {},
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

  group('a message drawn from an edit', () {
    Event ownEdit(EventStatus status) => buildTestEvent(
      room,
      eventId: 'txn-edit',
      senderId: me,
      status: status,
      originServerTs: noon.add(const Duration(minutes: 1)),
      content: {
        'msgtype': 'm.text',
        'body': '* fixed',
        'm.new_content': {'msgtype': 'm.text', 'body': 'fixed'},
        'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$a'},
      },
    );

    testWidgets('shows Not sent when the edit failed, and a tap resends the '
        'edit itself', (tester) async {
      final original = text(r'$a', sender: me, status: EventStatus.sent);
      await pumpTile(
        tester,
        original,
        events: [ownEdit(EventStatus.error), original],
      );

      expect(find.text('fixed'), findsOneWidget);
      expect(find.byType(NotSentRow), findsOneWidget);
      expect(find.byType(MessageMeta), findsNothing);

      await tester.tap(find.text('fixed'));
      await tester.pump(kDoubleTapTimeout);
      expect(resent.single.eventId, 'txn-edit');
      expect(resent.single.relationshipEventId, r'$a');
    });

    testWidgets('shows the clock while the edit is on its way', (tester) async {
      final original = text(r'$a', sender: me, status: EventStatus.sent);
      await pumpTile(
        tester,
        original,
        events: [ownEdit(EventStatus.sending), original],
      );

      expect(find.byType(NotSentRow), findsNothing);
      expect(find.byIcon(Icons.schedule), findsWidgets);
      expect(find.text('edited'), findsWidgets);
    });
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

      await pumpTile(tester, text(r'$a'), canRespond: false);
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

  testWidgets('a formatted body that only holds a mention renders as plain '
      'text', (tester) async {
    await pumpTile(
      tester,
      text(
        r'$a',
        body: 'hi @Alice',
        extra: {
          'format': 'org.matrix.custom.html',
          'formatted_body':
              'hi <a href="https://matrix.to/#/@alice:example.org">@Alice</a>',
          'm.mentions': {
            'user_ids': ['@alice:example.org'],
          },
        },
      ),
    );
    expect(find.byType(LinkifiedText), findsOneWidget);
    expect(find.byType(Html), findsNothing);
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
    await tester.pump(kDoubleTapTimeout);
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

  group('a forwarded copy', () {
    Event media(
      String id, {
      String msgtype = 'm.image',
      bool forwarded = true,
      Map<String, Object?> extra = const {},
    }) => buildTestEvent(
      room,
      eventId: id,
      senderId: bob,
      originServerTs: noon,
      status: EventStatus.synced,
      content: {
        'msgtype': msgtype,
        'body': '${id.substring(1)}.jpg',
        'url': 'mxc://example.org/${id.substring(1)}',
        'info': {'w': 400, 'h': 300, 'mimetype': 'image/jpeg', 'size': 3},
        if (forwarded) forwardedKey: true,
        ...extra,
      },
    );

    testWidgets('a forwarded photo, file and gallery show Forwarded above '
        'the media', (tester) async {
      await pumpTile(tester, media(r'$p'));
      expect(find.text('Forwarded'), findsOneWidget);
      expect(find.byType(ForwardIcon), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Forwarded')).dy,
        lessThan(tester.getTopLeft(find.byType(ImageMessage)).dy),
      );

      await pumpTile(tester, media(r'$f', msgtype: 'm.file'));
      expect(find.text('Forwarded'), findsOneWidget);

      final gallery = [
        for (final index in [0, 1])
          media(
            '\$g$index',
            extra: galleryGroupContent(id: 'new', index: index, count: 2),
          ),
      ];
      await pumpTile(tester, gallery.last, events: gallery, gallery: gallery);
      expect(find.byType(GalleryMessage), findsOneWidget);
      expect(find.text('Forwarded'), findsOneWidget);
    });

    testWidgets('an ordinary photo does not', (tester) async {
      await pumpTile(tester, media(r'$p', forwarded: false));

      expect(find.text('Forwarded'), findsNothing);
    });
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

  group('live location', () {
    late DateTime now;

    List<Override> liveOverrides() => [
      matrixClientProvider.overrideWithValue(client),
      liveLocationViewingProvider.overrideWith((ref) {
        final viewing = LiveLocationViewing(
          client: client,
          isOffline: () => false,
        );
        ref.onDispose(viewing.dispose);
        return viewing;
      }),
      liveLocationSharingProvider.overrideWith((ref) {
        final sharing = LiveLocationSharing(
          client: client,
          capture: FakeLiveLocationCapture(),
          isOffline: () => false,
          recipients: (_) async => const [],
        );
        ref.onDispose(sharing.dispose);
        return sharing;
      }),
      mapTilesProvider.overrideWith((ref) async => null),
    ];

    Event start() => buildTestEvent(
      room,
      eventId: '\$start',
      senderId: bob,
      originServerTs: now,
      content: liveLocationStartContent(
        shareId: 'share1',
        endsAt: now.add(const Duration(hours: 1)),
        duration: LiveLocationDuration.hour,
      ),
    );

    setUp(() {
      now = clock.now();
      client.rooms.add(room);
      encryptRoom(room);
    });

    testWidgets('a live share opens its map on the sender', (tester) async {
      room.setState(
        buildTestEvent(
          room,
          eventId: '\$live',
          senderId: bob,
          type: liveLocationStateType,
          stateKey: bob,
          originServerTs: now,
          content: LiveShareState(
            shareId: 'share1',
            deviceId: 'PHONE',
            endsAt: now.add(const Duration(hours: 1)),
          ).toContent(),
        ),
      );
      await pumpTile(tester, start(), overrides: liveOverrides());

      await tester.tap(find.byIcon(Icons.share_location_outlined).first);
      await tester.pump(kDoubleTapTimeout);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester
            .widget<LiveLocationMapPage>(find.byType(LiveLocationMapPage))
            .focus,
        bob,
      );
    });

    testWidgets('a live share keeps the map frame', (tester) async {
      room.setState(
        buildTestEvent(
          room,
          eventId: '\$live',
          senderId: bob,
          type: liveLocationStateType,
          stateKey: bob,
          originServerTs: now,
          content: LiveShareState(
            shareId: 'share1',
            deviceId: 'PHONE',
            endsAt: now.add(const Duration(hours: 1)),
          ).toContent(),
        ),
      );
      await pumpTile(tester, start(), overrides: liveOverrides());

      final bubble = tester.widget<MessageBubble>(find.byType(MessageBubble));
      expect(bubble.padding, const EdgeInsets.all(mediaInset));
      expect(
        tester.getSize(find.byType(MessageBubble)).width,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio * 2 / 3,
          0.5,
        ),
      );
    });

    testWidgets('an ended share reads like a deleted message, time and all', (
      tester,
    ) async {
      await pumpTile(tester, start(), overrides: liveOverrides());

      final bubble = tester.widget<MessageBubble>(find.byType(MessageBubble));
      expect(bubble.padding, isNot(const EdgeInsets.all(mediaInset)));
      expect(find.byType(MessageMeta), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(MessageMeta)).dy,
        closeTo(tester.getBottomLeft(find.text('Live location ended')).dy, 3),
      );
      expect(
        tester.getSize(find.byType(MessageBubble)).width,
        lessThan(
          tester.view.physicalSize.width / tester.view.devicePixelRatio * 2 / 3,
        ),
      );
    });

    testWidgets('an ended share reads as ended and opens nothing', (
      tester,
    ) async {
      await pumpTile(tester, start(), overrides: liveOverrides());

      expect(find.text('Live location ended'), findsOneWidget);
      await tester.tap(find.text('Live location ended'));
      await tester.pump(kDoubleTapTimeout);

      expect(find.byType(LiveLocationMapPage), findsNothing);
    });
  });
}
