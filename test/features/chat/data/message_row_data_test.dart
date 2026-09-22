import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/data/message_row_data.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';

import '../../../helpers/fake_matrix.dart';

const me = '@me:example.org';
const bob = '@bob:example.org';
const cat = '@cat:example.org';

void main() {
  late Room room;
  late StoredEventsFakeDatabaseApi db;
  final noon = DateTime(2026, 9, 20, 12);

  setUp(() {
    db = StoredEventsFakeDatabaseApi();
    room = buildTestRoom(buildTestClient(userId: me, database: db))
      ..partial = false;
    room.setState(
      User(bob, membership: 'join', displayName: 'Bob', room: room),
    );
    room.setState(User(me, membership: 'join', displayName: 'Me', room: room));
    room.setState(
      User(cat, membership: 'join', displayName: 'Cat', room: room),
    );
  });

  Event text(
    String id, {
    String sender = bob,
    DateTime? at,
    EventStatus? status,
    Map<String, Object?> extra = const {},
  }) => buildTestEvent(
    room,
    eventId: id,
    senderId: sender,
    originServerTs: at ?? noon,
    status: status ?? EventStatus.synced,
    content: {'msgtype': 'm.text', 'body': 'hello', ...extra},
  );

  Event reaction(String id, String target, String key, {String sender = cat}) =>
      buildTestEvent(
        room,
        eventId: id,
        senderId: sender,
        type: EventTypes.Reaction,
        originServerTs: noon,
        content: {
          'm.relates_to': {
            'rel_type': 'm.annotation',
            'event_id': target,
            'key': key,
          },
        },
      );

  Event edit(String id, String target, {String sender = bob}) => buildTestEvent(
    room,
    eventId: id,
    senderId: sender,
    originServerTs: noon.add(const Duration(minutes: 1)),
    content: {
      'msgtype': 'm.text',
      'body': '* fixed',
      'm.new_content': {'msgtype': 'm.text', 'body': 'fixed'},
      'm.relates_to': {'rel_type': 'm.replace', 'event_id': target},
    },
  );

  Future<Timeline> timelineOf(List<Event> events) {
    db.events = events;
    return room.getTimeline();
  }

  Future<MessageRowData> record(
    Event event, {
    List<Event>? events,
    Event? older,
    Event? newer,
    bool isLastOwn = false,
    List<Event>? gallery,
    List<int> galleryFailureIndexes = const [],
    bool canReply = true,
    bool linkPreviews = false,
    DateTime? now,
    bool use24Hour = true,
  }) async {
    final all = events ?? [event];
    final timeline = await timelineOf(all);
    addTearDown(timeline.cancelSubscriptions);
    return messageRowDataFor(
      event: event,
      timeline: timeline,
      index: {for (final e in all) e.eventId: e},
      older: older,
      newer: newer,
      isLastOwn: isLastOwn,
      gallery: gallery,
      galleryFailureIndexes: galleryFailureIndexes,
      canReply: canReply,
      linkPreviews: linkPreviews,
      now: now ?? noon,
      use24Hour: use24Hour,
    );
  }

  test('equal inputs give equal records and hashes', () async {
    final event = text(r'$m1');
    final a = await record(event);
    final b = await record(event);
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });

  test('status', () async {
    final sending = await record(
      text(r'$m1', sender: me, status: EventStatus.sending),
    );
    final sent = await record(
      text(r'$m1', sender: me, status: EventStatus.sent),
    );
    expect(sending, isNot(equals(sent)));
    expect(sending.metaStatus, MetaStatus.sending);
    expect(sent.metaStatus, MetaStatus.none);
  });

  test('type and messageType', () async {
    final encrypted = buildTestEvent(
      room,
      eventId: r'$m1',
      senderId: bob,
      type: EventTypes.Encrypted,
      originServerTs: noon,
      content: {'msgtype': MessageTypes.BadEncrypted, 'body': 'x'},
    );
    final a = await record(encrypted);
    final b = await record(text(r'$m1'));
    expect(a, isNot(equals(b)));
    expect(a.type, EventTypes.Encrypted);
    expect(b.messageType, MessageTypes.Text);
  });

  test('redacted', () async {
    final event = text(r'$m1');
    final before = await record(event);
    event.setRedactionEvent(
      buildTestEvent(
        room,
        eventId: r'$r',
        senderId: bob,
        type: EventTypes.Redaction,
        originServerTs: noon,
      ),
    );
    final after = await record(event);
    expect(before.redacted, isFalse);
    expect(after.redacted, isTrue);
    expect(before, isNot(equals(after)));
  });

  test('an edit changes displayEventId and edited', () async {
    final event = text(r'$m1');
    final plain = await record(event);
    final edited = await record(event, events: [edit(r'$e1', r'$m1'), event]);
    expect(plain.edited, isFalse);
    expect(plain.displayEventId, r'$m1');
    expect(edited.edited, isTrue);
    expect(edited.displayEventId, r'$e1');
    expect(plain, isNot(equals(edited)));
  });

  test('timeLabel follows the 24-hour setting', () async {
    final event = text(r'$m1', at: DateTime(2026, 9, 20, 9, 41));
    expect((await record(event)).timeLabel, '09:41');
    expect((await record(event, use24Hour: false)).timeLabel, '9:41 AM');
  });

  test('dayLabel only on the first message of a day', () async {
    final yesterday = text(r'$m0', at: DateTime(2026, 9, 19, 23, 58));
    final today = text(r'$m1', at: DateTime(2026, 9, 20, 0, 1));
    final laterToday = text(r'$m2', at: DateTime(2026, 9, 20, 0, 2));

    expect((await record(today, older: yesterday)).dayLabel, 'Today');
    expect((await record(laterToday, older: today)).dayLabel, isNull);
    expect((await record(yesterday)).dayLabel, 'Yesterday');
    expect(
      (await record(
        today,
        older: yesterday,
        now: DateTime(2026, 9, 21, 12),
      )).dayLabel,
      'Yesterday',
    );
  });

  test('sender rename', () async {
    final event = text(r'$m1');
    final before = await record(event);
    room.setState(
      User(bob, membership: 'join', displayName: 'Robert', room: room),
    );
    final after = await record(event);
    expect(before.senderName, 'Bob');
    expect(after.senderName, 'Robert');
    expect(before, isNot(equals(after)));
  });

  test('sender avatar', () async {
    final event = text(r'$m1');
    final before = await record(event);
    room.setState(
      User(
        bob,
        membership: 'join',
        displayName: 'Bob',
        avatarUrl: 'mxc://example.org/bob',
        room: room,
      ),
    );
    final after = await record(event);
    expect(before.senderAvatar, isNull);
    expect(after.senderAvatar, Uri.parse('mxc://example.org/bob'));
    expect(before, isNot(equals(after)));
  });

  group('startsRun', () {
    test('the oldest message starts a run', () async {
      expect((await record(text(r'$m1'))).startsRun, isTrue);
    });

    test('the same sender within the gap continues it', () async {
      final older = text(r'$m0', at: noon);
      final event = text(r'$m1', at: noon.add(const Duration(minutes: 4)));
      expect((await record(event, older: older)).startsRun, isFalse);
    });

    test('another sender starts one', () async {
      final older = text(r'$m0', sender: cat);
      expect((await record(text(r'$m1'), older: older)).startsRun, isTrue);
    });

    test('a gap over five minutes starts one', () async {
      final older = text(r'$m0', at: noon);
      final event = text(r'$m1', at: noon.add(const Duration(minutes: 6)));
      expect((await record(event, older: older)).startsRun, isTrue);
    });

    test('a hidden neighbor starts one', () async {
      final older = buildTestEvent(
        room,
        eventId: r'$s',
        senderId: bob,
        type: EventTypes.RoomName,
        stateKey: '',
        originServerTs: noon,
        content: {'name': 'x'},
      );
      expect((await record(text(r'$m1'), older: older)).startsRun, isTrue);
    });

    test('a new day starts one even inside the gap', () async {
      final older = text(r'$m0', at: DateTime(2026, 9, 19, 23, 59));
      final event = text(r'$m1', at: DateTime(2026, 9, 20, 0, 1));
      expect((await record(event, older: older)).startsRun, isTrue);
    });

    test('a hidden event never starts a run', () async {
      final hidden = buildTestEvent(
        room,
        eventId: r'$s',
        senderId: bob,
        type: EventTypes.RoomName,
        stateKey: '',
        originServerTs: noon,
        content: {'name': 'x'},
      );
      expect((await record(hidden)).startsRun, isFalse);
    });
  });

  test('endsRun mirrors startsRun of the newer message', () async {
    final event = text(r'$m1', at: noon);
    final close = text(r'$m2', at: noon.add(const Duration(minutes: 1)));
    final far = text(r'$m3', at: noon.add(const Duration(minutes: 9)));
    final other = text(r'$m4', sender: cat, at: noon);
    final nextDay = text(r'$m5', at: DateTime(2026, 9, 21, 0, 1));
    final lateEvent = text(r'$m6', at: DateTime(2026, 9, 20, 23, 59));

    expect((await record(event)).endsRun, isTrue);
    expect((await record(event, newer: close)).endsRun, isFalse);
    expect((await record(event, newer: far)).endsRun, isTrue);
    expect((await record(event, newer: other)).endsRun, isTrue);
    expect((await record(lateEvent, newer: nextDay)).endsRun, isTrue);

    final hidden = buildTestEvent(
      room,
      eventId: r'$s',
      senderId: bob,
      type: EventTypes.RoomName,
      stateKey: '',
      originServerTs: noon.add(const Duration(minutes: 1)),
      content: {'name': 'x'},
    );
    expect((await record(event, newer: hidden)).endsRun, isTrue);
  });

  test('position maps the run flags', () async {
    final a = text(r'$a', at: noon);
    final b = text(r'$b', at: noon.add(const Duration(minutes: 1)));
    final c = text(r'$c', at: noon.add(const Duration(minutes: 2)));
    expect((await record(a)).position, RunPosition.single);
    expect((await record(a, newer: b)).position, RunPosition.first);
    expect((await record(b, older: a, newer: c)).position, RunPosition.middle);
    expect((await record(c, older: b)).position, RunPosition.last);
  });

  group('reply target', () {
    Event replyTo(String target) => text(
      r'$reply',
      extra: {
        'm.relates_to': {
          'm.in_reply_to': {'event_id': target},
        },
      },
    );

    test('not loaded, then loaded', () async {
      final reply = replyTo(r'$m1');
      final missing = await record(reply);
      final loaded = await record(reply, events: [reply, text(r'$m1')]);
      expect(missing.replyToId, r'$m1');
      expect(missing.replyLoaded, isFalse);
      expect(loaded.replyLoaded, isTrue);
      expect(loaded.replyDisplayEventId, r'$m1');
      expect(missing, isNot(equals(loaded)));
    });

    test('edited', () async {
      final reply = replyTo(r'$m1');
      final target = text(r'$m1');
      final plain = await record(reply, events: [reply, target]);
      final edited = await record(
        reply,
        events: [edit(r'$e1', r'$m1'), reply, target],
      );
      expect(edited.replyDisplayEventId, r'$e1');
      expect(plain, isNot(equals(edited)));
    });

    test('decrypted late', () async {
      final reply = replyTo(r'$m1');
      final encrypted = buildTestEvent(
        room,
        eventId: r'$m1',
        senderId: bob,
        type: EventTypes.Encrypted,
        originServerTs: noon,
        content: {'msgtype': MessageTypes.BadEncrypted, 'body': 'x'},
      );
      final before = await record(reply, events: [reply, encrypted]);
      final after = await record(reply, events: [reply, text(r'$m1')]);
      expect(before.replyType, EventTypes.Encrypted);
      expect(after.replyType, EventTypes.Message);
      expect(before, isNot(equals(after)));
    });

    test('its sender is renamed', () async {
      final reply = replyTo(r'$m1');
      final target = text(r'$m1');
      final before = await record(reply, events: [reply, target]);
      room.setState(
        User(bob, membership: 'join', displayName: 'Robert', room: room),
      );
      final after = await record(reply, events: [reply, target]);
      expect(after.replySenderName, 'Robert');
      expect(before, isNot(equals(after)));
    });

    test('deleted', () async {
      final reply = replyTo(r'$m1');
      final target = text(r'$m1');
      final before = await record(reply, events: [reply, target]);
      target.setRedactionEvent(
        buildTestEvent(
          room,
          eventId: r'$r',
          senderId: bob,
          type: EventTypes.Redaction,
          originServerTs: noon,
        ),
      );
      final after = await record(reply, events: [reply, target]);
      expect(after.replyRedacted, isTrue);
      expect(before, isNot(equals(after)));
    });
  });

  test('reactions: count, key and mine', () async {
    final event = text(r'$m1');
    final none = await record(event);
    final one = await record(
      event,
      events: [reaction(r'$r1', r'$m1', '👍'), event],
    );
    final two = await record(
      event,
      events: [
        reaction(r'$r2', r'$m1', '👍', sender: me),
        reaction(r'$r1', r'$m1', '👍'),
        event,
      ],
    );
    final otherKey = await record(
      event,
      events: [reaction(r'$r1', r'$m1', '🎉'), event],
    );

    expect(none.reactions, isEmpty);
    expect(one.reactions, [('👍', 1, false)]);
    expect(two.reactions, [('👍', 2, true)]);
    expect(none, isNot(equals(one)));
    expect(one, isNot(equals(two)));
    expect(one, isNot(equals(otherKey)));
  });

  test(
    'read tick only on the last own sent message; read flips isRead',
    () async {
      final own = text(r'$m1', sender: me, status: EventStatus.sent, at: noon);
      final notLast = await record(own);
      final last = await record(own, isLastOwn: true);
      expect(notLast.showReadTick, isFalse);
      expect(notLast.metaStatus, MetaStatus.none);
      expect(last.showReadTick, isTrue);
      expect(last.metaStatus, MetaStatus.sent);

      room.receiptState = LatestReceiptState(
        global: LatestReceiptStateForTimeline(
          ownPrivate: null,
          ownPublic: null,
          latestOwnReceipt: null,
          otherUsers: {
            bob: LatestReceiptStateData(
              r'$later',
              noon.millisecondsSinceEpoch + 1000,
            ),
          },
        ),
      );
      final read = await record(own, isLastOwn: true);
      expect(read.isRead, isTrue);
      expect(read.metaStatus, MetaStatus.read);
      expect(last, isNot(equals(read)));

      final others = await record(text(r'$m2'), isLastOwn: true);
      expect(others.showReadTick, isFalse);
    },
  );

  test('gallery members, statuses and failed indexes', () async {
    final a = text(r'$g1', sender: me, status: EventStatus.sent);
    final b = text(r'$g2', sender: me, status: EventStatus.sending);
    final single = await record(a, gallery: [a]);
    final pair = await record(a, gallery: [a, b]);
    expect(pair.galleryIds, [r'$g1', r'$g2']);
    expect(pair.galleryStatuses, [EventStatus.sent, EventStatus.sending]);
    expect(single, isNot(equals(pair)));

    b.status = EventStatus.sent;
    expect(pair, isNot(equals(await record(a, gallery: [a, b]))));

    expect(
      await record(a, gallery: [a, b]),
      isNot(
        equals(await record(a, gallery: [a, b], galleryFailureIndexes: [2])),
      ),
    );
  });

  test('canReply and linkPreviews', () async {
    final event = text(r'$m1');
    expect(
      await record(event),
      isNot(equals(await record(event, canReply: false))),
    );
    expect(
      await record(event),
      isNot(equals(await record(event, linkPreviews: true))),
    );
  });

  test('own and direct flags', () async {
    expect((await record(text(r'$m1', sender: me))).isOwn, isTrue);
    expect((await record(text(r'$m1'))).isOwn, isFalse);
    expect((await record(text(r'$m1'))).isDirect, isFalse);
  });
}
