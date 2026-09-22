import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/notifications/notify_me.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:x');
    room = buildTestRoom(client);
    room.setState(User('@a:x', displayName: 'Alice', room: room));
  });

  EvaluatedPushRuleAction actionWith({
    bool notify = false,
    bool highlight = false,
  }) {
    final action = EvaluatedPushRuleAction();
    action.notify = notify;
    action.highlight = highlight;
    return action;
  }

  Event textEvent({
    String senderId = '@a:x',
    String body = 'hi',
    String type = EventTypes.Message,
    DateTime? originServerTs,
  }) => buildTestEvent(
    room,
    eventId: r'$1',
    senderId: senderId,
    type: type,
    originServerTs: originServerTs,
    content: {'msgtype': MessageTypes.Text, 'body': body},
  );

  MessageNotificationDecision decide(
    Event event, {
    EvaluatedPushRuleAction? pushRuleAction,
    NotifyMe notifyMe = NotifyMe.all,
    String? currentlyOpenRoomId,
  }) => messageNotificationFor(
    client,
    event,
    pushRuleAction: pushRuleAction ?? actionWith(notify: true),
    notifyMe: notifyMe,
    currentlyOpenRoomId: currentlyOpenRoomId,
  );

  test('notifies with room title + "sender: preview" body for a group message '
      'when the push rule says notify', () {
    final decision = decide(textEvent(body: 'hello there'));

    expect(decision.content, isNotNull);
    expect(decision.content!.roomId, room.id);
    expect(decision.content!.body, contains('hello there'));
    expect(decision.content!.isDirectChat, isFalse);
    expect(decision.refusal, isNull);
  });

  test('carries the triggering event\'s id — what "Mark as read" points '
      'setReadMarker at (message_notification_action.dart)', () {
    final decision = decide(textEvent());

    expect(decision.content!.eventId, r'$1');
  });

  Event agedEvent(Duration age) =>
      textEvent(originServerTs: DateTime.now().subtract(age));

  test('notifies for a message delayed by a distributor backlog', () {
    expect(decide(agedEvent(const Duration(minutes: 31))).content, isNotNull);
  });

  test('notifies for a message that is days old', () {
    expect(decide(agedEvent(const Duration(days: 2))).content, isNotNull);
  });

  test('does not notify when the push rule says not to', () {
    final decision = decide(textEvent(), pushRuleAction: actionWith());

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.pushRule);
  });

  test('does not notify for your own sent message', () {
    final decision = decide(textEvent(senderId: '@me:x'));

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.ownMessage);
  });

  test('does not notify for a room state event', () {
    final decision = decide(textEvent(type: EventTypes.RoomMember));

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.notDisplayable);
  });

  test('does not notify for an event that never decrypted', () {
    final event = buildTestEvent(
      room,
      eventId: r'$enc',
      senderId: '@a:x',
      type: EventTypes.Encrypted,
      content: {'algorithm': 'm.megolm.v1.aes-sha2', 'ciphertext': 'AAAA'},
    );

    final decision = decide(event);

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.notAMessage);
  });

  test('does not notify for an edit', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: {
        'msgtype': MessageTypes.Text,
        'body': '* edited',
        'm.relates_to': {'rel_type': RelationshipTypes.edit, 'event_id': r'$0'},
      },
    );

    final decision = decide(event);

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.notDisplayable);
  });

  test('does not notify for call-signaling msgtypes', () {
    for (final msgtype in ['im.zuno.call_invite', 'im.zuno.call_decline']) {
      final event = buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': msgtype, 'body': 'signaling'},
      );

      final decision = decide(event);

      expect(decision.content, isNull, reason: msgtype);
      expect(
        decision.refusal,
        MessageNotificationRefusal.notDisplayable,
        reason: msgtype,
      );
    }
  });

  test('does not notify for the currently-open room', () {
    final decision = decide(textEvent(), currentlyOpenRoomId: room.id);

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.roomOpen);
  });

  test('mentions-only requires highlight, not just notify', () {
    final decision = decide(
      textEvent(),
      pushRuleAction: actionWith(notify: true, highlight: false),
      notifyMe: NotifyMe.mentionsOnly,
    );

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.pushRule);
  });

  test('mentions-only notifies when highlight is set', () {
    final decision = decide(
      textEvent(),
      pushRuleAction: actionWith(notify: true, highlight: true),
      notifyMe: NotifyMe.mentionsOnly,
    );

    expect(decision.content, isNotNull);
  });

  MessageNotificationDecision decideSummary(CallSummaryStatus status) => decide(
    buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: CallSummary(
        callId: 'c1',
        kind: 'voice',
        status: status,
        durationMs: 0,
      ).toMessageContent(),
    ),
  );

  test('notifies for a missed-call summary', () {
    expect(decideSummary(CallSummaryStatus.missed).content, isNotNull);
  });

  test('does not notify for a declined-call summary', () {
    final decision = decideSummary(CallSummaryStatus.declined);

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.callSummaryNotMissed);
  });

  test('does not notify for an ended-call summary', () {
    final decision = decideSummary(CallSummaryStatus.ended);

    expect(decision.content, isNull);
    expect(decision.refusal, MessageNotificationRefusal.callSummaryNotMissed);
  });

  test('describes a photo by its caption, with no thumbnail to fetch', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: {
        'msgtype': MessageTypes.Image,
        'body': 'a cat',
        'filename': 'cat.jpg',
        'url': 'mxc://x/cat',
      },
    );

    final decision = decide(event);

    expect(decision.content, isNotNull);
    expect(decision.content!.body, contains('a cat'));
    expect(decision.content!.text, contains('a cat'));
    expect(decision.content!.isPhoto, isTrue);
  });

  test('a text message is not marked as a photo', () {
    expect(decide(textEvent()).content!.isPhoto, isFalse);
  });

  test('carries the sender and the time so the notification can be a '
      'conversation line', () {
    final at = DateTime.utc(2031, 2, 3, 4, 5);
    final decision = decide(textEvent(originServerTs: at));

    final content = decision.content!;
    expect(content.senderId, '@a:x');
    expect(content.senderName, 'Alice');
    expect(content.timestamp, at);
    expect(content.text, 'hi');
    expect(content.unreadCount, room.notificationCount);
  });

  test('every refusal has a distinct, greppable label', () {
    final labels = MessageNotificationRefusal.values
        .map((refusal) => refusal.label)
        .toList();

    expect(labels.toSet(), hasLength(labels.length));
    for (final label in labels) {
      expect(
        RegExp(r'^[a-z][a-z-]*[a-z]$').hasMatch(label),
        isTrue,
        reason: label,
      );
    }
  });
}
