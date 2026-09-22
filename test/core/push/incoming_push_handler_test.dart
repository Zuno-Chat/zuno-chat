import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

const ringNotificationId = 4002;

class _ScriptedClient extends Client {
  _ScriptedClient() : super('test', database: FakeDatabaseApi());

  Event? resolved;
  Object? throws;
  Completer<Event?>? delayed;
  int resolveCalls = 0;

  int pushRuleChecks = 0;

  @override
  PushruleEvaluator get pushruleEvaluator =>
      _countedEvaluator(++pushRuleChecks);

  PushruleEvaluator _countedEvaluator(int _) => PushruleEvaluator.fromRuleset(
    PushRuleSet(
      underride: [
        PushRule(
          ruleId: '.m.rule.message',
          default$: true,
          enabled: true,
          conditions: [
            PushCondition(
              kind: 'event_match',
              key: 'type',
              pattern: 'm.room.message',
            ),
          ],
          actions: ['notify'],
        ),
      ],
    ),
  );

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    resolveCalls++;
    final pending = delayed;
    if (pending != null) return pending.future;
    final failure = throws;
    if (failure != null) throw failure;
    return resolved;
  }
}

void main() {
  late _ScriptedClient client;
  late Room room;
  late RecordedNotifications notifications;
  late RecordedCallStyleCalls callStyle;

  PushNotification push({String? roomId = '!room:example.org'}) =>
      PushNotification(devices: const [], eventId: r'$event', roomId: roomId);

  Event message({
    String senderId = '@bob:example.org',
    String body = 'hello',
    DateTime? originServerTs,
  }) => buildTestEvent(
    room,
    eventId: r'$event',
    senderId: senderId,
    originServerTs: originServerTs,
    content: {'msgtype': 'm.text', 'body': body},
  );

  Event callInvite({String callId = 'call1'}) => buildTestEvent(
    room,
    eventId: r'$event',
    senderId: '@bob:example.org',
    content: {'msgtype': callInviteMsgtype, 'call_id': callId, 'kind': 'voice'},
  );

  Event callSummary({
    String callId = 'call1',
    required CallSummaryStatus status,
  }) => buildTestEvent(
    room,
    eventId: r'$event',
    senderId: '@bob:example.org',
    content: CallSummary(
      callId: callId,
      kind: 'voice',
      status: status,
      durationMs: 12000,
    ).toMessageContent(),
  );

  Future<IncomingPushOutcome> handle({NotifyMe notifyMe = NotifyMe.all}) =>
      handleIncomingPushNotification(client, push(), notifyMe: notifyMe);

  List<String> mockPushNotices(Map<String, String> notices) {
    final outstanding = Map.of(notices);
    final taken = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zuno/conversations'), (
          call,
        ) async {
          if (call.method != 'takePushNotice') return null;
          final args = (call.arguments as Map).cast<String, Object?>();
          final roomId = args['roomId'] as String?;
          final eventId = args['eventId'] as String?;
          taken.add('$roomId/$eventId');
          if (outstanding[roomId] != eventId) return false;
          outstanding.remove(roomId);
          return true;
        });
    return taken;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ringRateLimiter.clear();
    notifications = installFakeLocalNotifications();
    callStyle = installFakeCallStyleChannel();
    installSilentNotificationSideChannels();
    client = _ScriptedClient();
    client.setUserId('@me:example.org');
    room = buildTestRoom(client);
    for (final (id, name) in const [
      ('@bob:example.org', 'Bob'),
      ('@me:example.org', 'Me'),
    ]) {
      room.setState(
        buildTestEvent(
          room,
          eventId: '\$member-$id',
          senderId: id,
          type: EventTypes.RoomMember,
          stateKey: id,
          content: {'membership': 'join', 'displayname': name},
        ),
      );
    }
  });

  group('when the event cannot be fetched', () {
    test('still notifies, routed to the room the push named', () async {
      client.throws = Exception('no network');

      expect(await handle(), IncomingPushOutcome.message);

      expect(notifications.single.body, 'Tap to open');
      expect(notifications.single.payload, contains('!room:example.org'));
    });

    test('still offers Reply and Mark as read, keyed to the push\'s own '
        'eventId', () async {
      client.throws = Exception('no network');

      expect(await handle(), IncomingPushOutcome.message);

      expect(notifications.single.payload, contains(r'"eventId":"$event"'));
      final actions = (notifications.single.android['actions'] as List)
          .cast<Map>()
          .map((a) => a['id']);
      expect(actions, containsAll(['reply', 'mark_read']));
    });

    test('stays silent when the push names no room to open', () async {
      client.throws = Exception('no network');
      final outcome = await handleIncomingPushNotification(
        client,
        push(roomId: null),
        notifyMe: NotifyMe.all,
      );

      expect(outcome, IncomingPushOutcome.ignored);
      expect(notifications.shown, isEmpty);
    });
  });

  test(
    'stays silent for an event the server says is not worth showing',
    () async {
      client.resolved = null;

      expect(await handle(), IncomingPushOutcome.ignored);
      expect(notifications.shown, isEmpty);
    },
  );

  test('an unresolved push cancels the native notice for its room', () async {
    client.resolved = null;
    final notification = push();
    final taken = mockPushNotices({
      notification.roomId!: notification.eventId!,
    });

    await handleIncomingPushNotification(
      client,
      notification,
      notifyMe: NotifyMe.all,
    );

    expect(taken, ['${notification.roomId}/${notification.eventId}']);
    expect(
      notifications.cancelled,
      contains(messageNotificationIdFor(notification.roomId!)),
    );
  });

  test('stays silent for a message in the room the user is looking at, '
      'the same way the sync path does', () async {
    client.resolved = message();

    final outcome = await handleIncomingPushNotification(
      client,
      push(),
      notifyMe: NotifyMe.all,
      currentlyOpenRoomId: room.id,
    );

    expect(outcome, IncomingPushOutcome.ignored);
    expect(notifications.shown, isEmpty);
  });

  group('calls', () {
    test('rings for a fresh invite', () async {
      client.resolved = callInvite();

      expect(await handle(), IncomingPushOutcome.callRinging);

      final args = callStyle.lastShow.arguments as Map;
      expect(args['roomId'], '!room:example.org');
      expect(args['callId'], 'call1');
    });

    test('does not ring for a call already resolved on this device', () async {
      final prefs = await SharedPreferences.getInstance();
      await markCallResolvedOnDisk(prefs, 'call1');
      client.resolved = callInvite(callId: 'call1');

      expect(await handle(), IncomingPushOutcome.ignored);
      expect(notifications.shown, isEmpty);
    });

    test('a summary cancels the ring and remembers the call is over', () async {
      client.resolved = callSummary(status: CallSummaryStatus.ended);

      expect(await handle(), IncomingPushOutcome.ignored);

      expect(
        callStyle.calls.map((c) => c.method),
        contains('cancelIncomingCallStyle'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(readResolvedCallIds(prefs), contains('call1'));
    });

    test(
      'a summary for a call that just rang does not cancel it instantly',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await saveRingingCall(prefs, (
          roomId: room.id,
          callId: 'call1',
          callerId: '@bob:example.org',
          isVideo: false,
        ));
        client.resolved = callSummary(status: CallSummaryStatus.ended);

        final outcome = handle();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          callStyle.calls.map((c) => c.method),
          isNot(contains('cancelIncomingCallStyle')),
          reason: 'the ring just posted is still within its grace window',
        );

        await outcome;
        expect(
          callStyle.calls.map((c) => c.method),
          contains('cancelIncomingCallStyle'),
          reason: 'the summary must still take the ring down eventually',
        );
      },
    );

    test(
      'a call that just ended in front of the user is not announced',
      () async {
        client.resolved = callSummary(status: CallSummaryStatus.ended);

        expect(await handle(), IncomingPushOutcome.ignored);
        expect(notifications.shown, isEmpty);
      },
    );

    test(
      'an ended call is dropped before the message filter is consulted',
      () async {
        client.resolved = callSummary(status: CallSummaryStatus.ended);

        expect(await handle(), IncomingPushOutcome.ignored);
        expect(client.pushRuleChecks, 0);
      },
    );

    test('a declined call is not announced either', () async {
      client.resolved = callSummary(status: CallSummaryStatus.declined);

      expect(await handle(), IncomingPushOutcome.ignored);
      expect(notifications.shown, isEmpty);
    });

    test('a missed call is announced', () async {
      client.resolved = callSummary(status: CallSummaryStatus.missed);

      expect(await handle(), IncomingPushOutcome.message);
      expect(notifications.single.body, contains('Missed'));
    });
  });

  group('messages', () {
    test('notifies for someone else\'s message', () async {
      client.resolved = message(body: 'are you around?');

      expect(await handle(), IncomingPushOutcome.message);

      expect(notifications.single.body, 'Bob: are you around?');
      expect(notifications.single.id, isNot(ringNotificationId));
    });

    test(
      'attaches Reply and Mark as read, keyed to the resolved event',
      () async {
        client.resolved = message(body: 'are you around?');

        expect(await handle(), IncomingPushOutcome.message);

        expect(notifications.single.payload, contains(r'"eventId":"$event"'));
        final actions = (notifications.single.android['actions'] as List)
            .cast<Map>()
            .map((a) => a['id']);
        expect(actions, containsAll(['reply', 'mark_read']));
      },
    );

    test('stays silent for a message you sent yourself', () async {
      client.resolved = message(senderId: '@me:example.org');

      expect(await handle(), IncomingPushOutcome.ignored);
      expect(notifications.shown, isEmpty);
    });

    test(
      'notifies for a message that has been queued for half an hour',
      () async {
        client.resolved = message(
          body: 'sent while you were offline',
          originServerTs: DateTime.now().subtract(const Duration(minutes: 31)),
        );

        expect(await handle(), IncomingPushOutcome.message);
        expect(
          notifications.single.body,
          contains('sent while you were offline'),
        );
      },
    );

    test(
      'notifies for a photo message by its caption, with no download',
      () async {
        client.resolved = buildTestEvent(
          room,
          eventId: r'$event',
          senderId: '@bob:example.org',
          content: {
            'msgtype': MessageTypes.Image,
            'body': 'a cat',
            'filename': 'cat.jpg',
            'url': 'mxc://x/cat',
          },
        );

        expect(await handle(), IncomingPushOutcome.message);

        expect(notifications.single.body, contains('a cat'));
      },
    );

    test(
      'stays silent for a plain message when set to mentions only',
      () async {
        client.resolved = message();

        expect(
          await handle(notifyMe: NotifyMe.mentionsOnly),
          IncomingPushOutcome.ignored,
        );
        expect(notifications.shown, isEmpty);
      },
    );
  });

  group('slow resolution', () {
    const after = Duration(milliseconds: 30);
    late Completer<Event?> pending;
    late int roomNotificationId;

    setUp(() {
      pending = Completer<Event?>();
      client.delayed = pending;
      roomNotificationId = messageNotificationIdFor(room.id);
    });

    Future<IncomingPushOutcome> handleSlowly() =>
        handleIncomingPushNotification(
          client,
          push(),
          notifyMe: NotifyMe.all,
          placeholderAfter: after,
        );

    List<Map<String, Object?>> linesOf(ShownNotification n) =>
        ((n.android['styleInformation'] as Map)['messages'] as List)
            .cast<Map>()
            .map((m) => m.cast<String, Object?>())
            .toList();

    test(
      'posts a routable placeholder first, then upgrades it in place',
      () async {
        final outcome = handleSlowly();
        await Future<void>.delayed(after * 3);

        final placeholder = notifications.shown
            .where((n) => n.id == roomNotificationId)
            .single;
        expect(linesOf(placeholder).single['text'], 'New message');
        expect(placeholder.payload, contains(room.id));

        notifications.active = [
          {
            'id': roomNotificationId,
            'channelId': 'group_messages',
            'payload': '',
          },
        ];
        pending.complete(message(body: 'hello'));
        expect(await outcome, IncomingPushOutcome.message);

        final posts = notifications.shown.where(
          (n) => n.id == roomNotificationId,
        );
        expect(posts, hasLength(2));
        expect(linesOf(posts.last).map((l) => l['text']), ['hello']);
        expect(posts.last.android['onlyAlertOnce'], isTrue);
      },
    );

    test(
      'stays silent all through when a native notice already alerted',
      () async {
        mockPushNotices({room.id: r'$event'});
        notifications.active = [
          {
            'id': roomNotificationId,
            'channelId': 'group_messages',
            'payload': '',
          },
        ];

        final outcome = handleSlowly();
        await Future<void>.delayed(after * 3);
        pending.complete(message(body: 'hello'));
        expect(await outcome, IncomingPushOutcome.message);

        final posts = notifications.shown
            .where((n) => n.id == roomNotificationId)
            .toList();
        expect(posts, hasLength(2));
        expect(posts.map((n) => n.android['onlyAlertOnce']), [isTrue, isTrue]);
        expect(linesOf(posts.last).map((l) => l['text']), ['hello']);
      },
    );

    test(
      'retracts the placeholder when the event turns out to be nothing',
      () async {
        final outcome = handleSlowly();
        await Future<void>.delayed(after * 3);
        notifications.active = [
          {
            'id': roomNotificationId,
            'channelId': 'group_messages',
            'payload': '',
          },
        ];

        pending.complete(null);
        expect(await outcome, IncomingPushOutcome.ignored);

        expect(notifications.cancelled, contains(roomNotificationId));
      },
    );

    test('keeps the placeholder standing when the fetch fails', () async {
      final outcome = handleSlowly();
      await Future<void>.delayed(after * 3);

      pending.completeError(Exception('offline'));
      expect(await outcome, IncomingPushOutcome.message);

      expect(notifications.cancelled, isNot(contains(roomNotificationId)));
      expect(
        notifications.shown.where((n) => n.id == roomNotificationId),
        hasLength(1),
      );
    });

    test('a fast fetch never shows a placeholder', () async {
      pending.complete(message(body: 'quick'));

      expect(await handleSlowly(), IncomingPushOutcome.message);

      final posts = notifications.shown.where(
        (n) => n.id == roomNotificationId,
      );
      expect(posts, hasLength(1));
      expect(linesOf(posts.single).single['text'], 'quick');
    });
  });

  group('refusal logging', () {
    late List<String> lines;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      lines = [];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
    });

    tearDown(() => debugPrint = originalDebugPrint);

    String refusalLine() =>
        lines.singleWhere((line) => line.contains('not notifying'));

    test('names the branch that dropped it', () async {
      client.resolved = message(senderId: '@me:example.org');

      expect(await handle(), IncomingPushOutcome.ignored);
      expect(refusalLine(), contains('own-message'));
    });

    test('a different cause reads differently', () async {
      client.resolved = message();

      expect(
        await handle(notifyMe: NotifyMe.mentionsOnly),
        IncomingPushOutcome.ignored,
      );
      expect(refusalLine(), contains('push-rule'));
      expect(refusalLine(), isNot(contains('own-message')));
    });

    test('says nothing when it did notify', () async {
      client.resolved = message();

      expect(await handle(), IncomingPushOutcome.message);
      expect(lines.where((line) => line.contains('not notifying')), isEmpty);
    });

    test('never writes the message body', () async {
      client.resolved = message(
        senderId: '@me:example.org',
        body: 'the account number is 4471',
      );

      await handle();

      expect(lines, isNot(contains(contains('4471'))));
    });
  });

  test('notifies for a room invitation', () async {
    client.resolved = buildTestEvent(
      room,
      eventId: r'$event',
      senderId: '@bob:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@me:example.org',
      content: {'membership': 'invite'},
    );

    expect(await handle(), IncomingPushOutcome.message);
    expect(notifications.single.body, 'Invited you to chat');
  });

  test('an invitation posts over the native notice instead of cancelling '
      'it', () async {
    mockPushNotices({room.id: r'$event'});
    notifications.active = [
      {
        'id': messageNotificationIdFor(room.id),
        'channelId': 'direct_messages',
        'payload': '',
      },
    ];
    client.resolved = buildTestEvent(
      room,
      eventId: r'$event',
      senderId: '@bob:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@me:example.org',
      content: {'membership': 'invite'},
    );

    expect(await handle(), IncomingPushOutcome.message);

    expect(notifications.cancelled, isEmpty);
    expect(notifications.single.body, 'Invited you to chat');
    expect(notifications.single.android['onlyAlertOnce'], isTrue);
  });

  test('a room invitation gets no Reply/Mark-as-read actions', () async {
    client.resolved = buildTestEvent(
      room,
      eventId: r'$event',
      senderId: '@bob:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@me:example.org',
      content: {'membership': 'invite'},
    );

    expect(await handle(), IncomingPushOutcome.message);
    expect(notifications.single.android['actions'], anyOf(isNull, isEmpty));
  });
}
