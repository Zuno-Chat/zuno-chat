import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/media_gallery_group.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/data/pending_attachment_send.dart';
import 'package:zuno/features/chat/presentation/date_divider.dart';
import 'package:zuno/features/chat/presentation/empty_room_notice.dart';
import 'package:zuno/features/chat/presentation/message_contents/pending_attachment_tile.dart';
import 'package:zuno/features/chat/presentation/message_list_view.dart';
import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/reply_target_cache.dart';
import 'package:zuno/features/chat/presentation/swipe_to_reply.dart';
import 'package:zuno/core/matrix/send_progress.dart';

import '../../../helpers/fake_matrix.dart';

const me = '@me:example.org';
const bob = '@bob:example.org';

void main() {
  late Room room;
  late StoredEventsFakeDatabaseApi db;
  late ValueNotifier<PendingAttachmentSend?> pendingSend;
  late void Function() rebuild;
  final noon = DateTime(2026, 9, 20, 12);

  setUp(() {
    db = StoredEventsFakeDatabaseApi();
    room = buildTestRoom(buildTestClient(userId: me, database: db))
      ..partial = false;
    room.setState(
      User(bob, membership: 'join', displayName: 'Bob', room: room),
    );
    room.setState(User(me, membership: 'join', displayName: 'Me', room: room));
    pendingSend = ValueNotifier(null);
    addTearDown(pendingSend.dispose);
  });

  Event text(String id, {String sender = bob, DateTime? at}) => buildTestEvent(
    room,
    eventId: id,
    senderId: sender,
    originServerTs: at ?? noon,
    status: EventStatus.synced,
    content: {'msgtype': 'm.text', 'body': 'body of $id'},
  );

  Future<Timeline> timelineOf(WidgetTester tester, List<Event> events) async {
    db.events = events;
    final timeline = (await tester.runAsync(room.getTimeline))!;
    addTearDown(timeline.cancelSubscriptions);
    return timeline;
  }

  Future<void> pumpList(
    WidgetTester tester,
    Timeline Function() timeline, {
    List<FailedMediaSend> failedSends = const [],
  }) async {
    final cache = ReplyTargetCache((id) async => null);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: zunoLightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = () => setState(() {});
                return MessageListView(
                  room: room,
                  timeline: timeline(),
                  controller: controller,
                  showHiddenMessages: false,
                  linkPreviews: false,
                  canReply: true,
                  failedSends: failedSends,
                  pendingSend: pendingSend,
                  replyTargets: cache,
                  onLongPress: (_, _) {},
                  onSwipeReply: (_) {},
                  onResend: (_) {},
                  onRetryFailedSend: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  MessageTile tile(WidgetTester tester, String id) =>
      tester.widget<MessageTile>(find.byKey(ValueKey(id)));

  testWidgets(
    'an unchanged message keeps the identical widget across rebuilds',
    (tester) async {
      final timeline = await timelineOf(tester, [text(r'$m2'), text(r'$m1')]);
      await pumpList(tester, () => timeline);
      final before = tile(tester, r'$m1');

      rebuild();
      await tester.pump();

      expect(identical(tile(tester, r'$m1'), before), isTrue);
    },
  );

  testWidgets('a reaction rebuilds only its message', (tester) async {
    final timeline = await timelineOf(tester, [text(r'$m2'), text(r'$m1')]);
    await pumpList(tester, () => timeline);
    final first = tile(tester, r'$m1');
    final second = tile(tester, r'$m2');

    final reaction = buildTestEvent(
      room,
      eventId: r'$r1',
      senderId: me,
      type: EventTypes.Reaction,
      originServerTs: noon,
      content: {
        'm.relates_to': {
          'rel_type': 'm.annotation',
          'event_id': r'$m1',
          'key': '👍',
        },
      },
    );
    timeline.events.insert(0, reaction);
    timeline.addAggregatedEvent(reaction);
    rebuild();
    await tester.pump();

    expect(identical(tile(tester, r'$m1'), first), isFalse);
    expect(identical(tile(tester, r'$m2'), second), isTrue);
    expect(find.text('👍 1'), findsOneWidget);
  });

  testWidgets('a new timeline clears the memo', (tester) async {
    final events = [text(r'$m1')];
    var timeline = await timelineOf(tester, events);
    await pumpList(tester, () => timeline);
    final before = tile(tester, r'$m1');

    timeline = await timelineOf(tester, events);
    rebuild();
    await tester.pump();

    expect(identical(tile(tester, r'$m1'), before), isFalse);
  });

  testWidgets('a day label sits above the first message of each day', (
    tester,
  ) async {
    final timeline = await timelineOf(tester, [
      text(r'$m3', at: DateTime(2025, 3, 2, 9, 1)),
      text(r'$m2', at: DateTime(2025, 3, 2, 9)),
      text(r'$m1', at: DateTime(2025, 3, 1, 9)),
    ]);
    await pumpList(tester, () => timeline);

    expect(find.byType(DateDivider), findsNWidgets(2));
    expect(find.text('March 1, 2025'), findsOneWidget);
    expect(find.text('March 2, 2025'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('March 2, 2025')).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey(r'$m2'))).dy),
    );
  });

  testWidgets('exhausted history shows No earlier messages', (tester) async {
    final timeline = await timelineOf(tester, [text(r'$m1')]);
    await tester.runAsync(timeline.requestHistory);
    await pumpList(tester, () => timeline);

    expect(timeline.canRequestHistory, isFalse);
    expect(find.text('No earlier messages'), findsOneWidget);
    expect(find.byType(EmptyRoomNotice), findsNothing);
  });

  testWidgets('a chat with nothing to show has the empty notice', (
    tester,
  ) async {
    room.setState(
      StrippedStateEvent(
        type: EventTypes.Encryption,
        senderId: bob,
        stateKey: '',
        content: {'algorithm': 'm.megolm.v1.aes-sha2'},
      ),
    );
    final timeline = await timelineOf(tester, [
      buildTestEvent(
        room,
        eventId: r'$create',
        senderId: bob,
        type: EventTypes.RoomCreate,
        stateKey: '',
        originServerTs: noon,
        content: {'creator': bob},
      ),
    ]);
    await tester.runAsync(timeline.requestHistory);
    await pumpList(tester, () => timeline);

    expect(find.byType(EmptyRoomNotice), findsOneWidget);
    expect(find.text('No earlier messages'), findsNothing);
  });

  testWidgets('an upload tick rebuilds only the upload tile', (tester) async {
    final timeline = await timelineOf(tester, [text(r'$m1')]);
    await pumpList(tester, () => timeline);
    final before = tile(tester, r'$m1');
    expect(find.byType(PendingAttachmentTile), findsNothing);

    pendingSend.value = PendingAttachmentSend(
      eventId: 'txid1',
      kind: SendMediaKind.file,
      stageProgress: 0.25,
    );
    await tester.pump();
    expect(find.byType(PendingAttachmentTile), findsOneWidget);
    expect(find.textContaining('25%'), findsOneWidget);

    pendingSend.value = pendingSend.value!.withStage(
      pendingSend.value!.stage,
      0.5,
    );
    await tester.pump();
    expect(find.textContaining('50%'), findsOneWidget);
    expect(identical(tile(tester, r'$m1'), before), isTrue);
  });

  testWidgets('a failed gallery with no surviving member gets its own tile', (
    tester,
  ) async {
    final timeline = await timelineOf(tester, [text(r'$m1')]);
    await pumpList(
      tester,
      () => timeline,
      failedSends: const [
        FailedMediaSend(gallery: GalleryGroupRef(id: 'g1', index: 0, count: 2)),
      ],
    );

    expect(find.byType(FailedGalleryTile), findsOneWidget);
    expect(find.byKey(const ValueKey(r'$m1')), findsOneWidget);
  });

  testWidgets('a new message at the bottom keeps the state of the others', (
    tester,
  ) async {
    final timeline = await timelineOf(tester, [text(r'$m2'), text(r'$m1')]);
    await pumpList(tester, () => timeline);
    State swipeState(String id) => tester.state(
      find.descendant(
        of: find.byKey(ValueKey(id)),
        matching: find.byType(SwipeToReply),
      ),
    );
    final before = swipeState(r'$m1');

    timeline.events.insert(
      0,
      text(r'$m3', at: noon.add(const Duration(minutes: 1))),
    );
    rebuild();
    await tester.pump();

    expect(find.byKey(const ValueKey(r'$m3')), findsOneWidget);
    expect(identical(swipeState(r'$m1'), before), isTrue);
  });

  testWidgets('a reply quote follows its target being decrypted late', (
    tester,
  ) async {
    final encrypted = buildTestEvent(
      room,
      eventId: r'$t',
      senderId: bob,
      type: EventTypes.Encrypted,
      originServerTs: noon,
      status: EventStatus.synced,
      content: {'msgtype': MessageTypes.BadEncrypted, 'body': 'x'},
    );
    final reply = buildTestEvent(
      room,
      eventId: r'$r',
      senderId: me,
      originServerTs: noon.add(const Duration(minutes: 1)),
      status: EventStatus.synced,
      content: {
        'msgtype': 'm.text',
        'body': 'on it',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$t'},
        },
      },
    );
    final timeline = await timelineOf(tester, [reply, encrypted]);
    await pumpList(tester, () => timeline);
    expect(find.textContaining('the secret plan'), findsNothing);

    final decrypted = buildTestEvent(
      room,
      eventId: r'$t',
      senderId: bob,
      originServerTs: noon,
      status: EventStatus.synced,
      content: {'msgtype': 'm.text', 'body': 'the secret plan'},
    );
    timeline.events[timeline.events.indexOf(encrypted)] = decrypted;
    rebuild();
    await tester.pump();

    expect(
      find.textContaining('the secret plan', findRichText: true),
      findsNWidgets(2),
    );
  });
}
