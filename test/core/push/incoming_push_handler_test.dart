import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/hybrid_fake_async.dart';

class _ScriptedClient extends Client {
  _ScriptedClient() : super('test', database: FakeDatabaseApi());

  Event? resolved;
  final events = <String, Event>{};
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
    final scripted = events[notification.eventId];
    if (scripted != null) return scripted;
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

  PushNotification push({
    String? roomId = '!room:example.org',
    String eventId = r'$event',
  }) => PushNotification(devices: const [], eventId: eventId, roomId: roomId);

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

  Event callInvite({String callId = 'call1', String eventId = r'$event'}) =>
      buildTestEvent(
        room,
        eventId: eventId,
        senderId: '@bob:example.org',
        content: {
          'msgtype': callInviteMsgtype,
          'call_id': callId,
          'kind': 'voice',
        },
      );

  Event callSummary({
    String callId = 'call1',
    required CallSummaryStatus status,
    String eventId = r'$event',
  }) => buildTestEvent(
    room,
    eventId: eventId,
    senderId: '@bob:example.org',
    content: CallSummary(
      callId: callId,
      kind: 'voice',
      status: status,
      durationMs: 12000,
    ).toMessageContent(),
  );

  Future<IncomingPushOutcome> handle({
    NotifyMe notifyMe = NotifyMe.all,
    String eventId = r'$event',
  }) => handleIncomingPushNotification(
    client,
    push(eventId: eventId),
    notifyMe: notifyMe,
  );

  Iterable<String> callStyleMethods() => callStyle.calls.map((c) => c.method);

  Future<String?> rememberedCallId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return readRingingCall(prefs)?.callId;
  }

  Future<Set<String>> resolvedCallIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return readResolvedCallIds(prefs);
  }

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

    group('with a call already live in this app', () {
      late ProviderContainer container;

      setUp(() {
        container = ProviderContainer();
        container
            .read(activeCallProvider.notifier)
            .set(
              CallSession.forIncoming(
                room: room,
                callId: 'live',
                kind: CallKind.voice,
              ),
            );
      });
      tearDown(() => container.dispose());

      test('does not ring over it', () async {
        client.resolved = callInvite();

        expect(await handle(), IncomingPushOutcome.ignored);
        expect(callStyleMethods(), isNot(contains('showIncomingCallStyle')));
        expect(notifications.shown, isEmpty);
      });

      test('rings again once that call has ended', () async {
        container.read(activeCallProvider.notifier).set(null);
        client.resolved = callInvite();

        expect(await handle(), IncomingPushOutcome.callRinging);
      });

      test('rings again once the app has gone away', () async {
        container.dispose();
        client.resolved = callInvite();

        expect(await handle(), IncomingPushOutcome.callRinging);
      });
    });

    group('with another call already ringing', () {
      const ringingCallId = 'ringing-call';

      setUp(() async {
        await saveRingingCall(await SharedPreferences.getInstance(), (
          roomId: room.id,
          callId: ringingCallId,
          callerId: '@bob:example.org',
          isVideo: false,
        ));
        notifications.active = [ringNotificationOnScreen()];
      });

      test('does not ring over it', () async {
        client.resolved = callInvite(callId: 'call1');

        expect(await handle(), IncomingPushOutcome.ignored);
        expect(callStyleMethods(), isNot(contains('showIncomingCallStyle')));
        expect(notifications.shown, isEmpty);
        expect(await rememberedCallId(), ringingCallId);
      });

      test('still rings for the call that is ringing', () async {
        client.resolved = callInvite(callId: ringingCallId);

        expect(await handle(), IncomingPushOutcome.callRinging);
        expect((callStyle.lastShow.arguments as Map)['callId'], ringingCallId);
      });

      test('rings once that call is over, though its notification is still '
          'up', () async {
        await markCallResolvedOnDisk(
          await SharedPreferences.getInstance(),
          ringingCallId,
        );
        client.resolved = callInvite(callId: 'call1');

        expect(await handle(), IncomingPushOutcome.callRinging);
        expect((callStyle.lastShow.arguments as Map)['callId'], 'call1');
        expect(await rememberedCallId(), 'call1');
      });

      test('a call dialled again while the summary of that call waits out '
          'its ring grace still rings, and the summary leaves the new ring '
          'up', () async {
        client.events.addAll({
          r'$summary': callSummary(
            callId: ringingCallId,
            status: CallSummaryStatus.ended,
            eventId: r'$summary',
          ),
          r'$redial': callInvite(callId: 'call1', eventId: r'$redial'),
        });
        final time = FakeAsync();
        IncomingPushOutcome? summaryOutcome;
        time.run((_) {
          handle(eventId: r'$summary').then((o) => summaryOutcome = o);
        });
        await time.settle();

        expect(
          await handle(eventId: r'$redial'),
          IncomingPushOutcome.callRinging,
        );
        expect((callStyle.lastShow.arguments as Map)['callId'], 'call1');
        callStyle.clear();

        await time.advance(const Duration(seconds: 3));
        expect(summaryOutcome, IncomingPushOutcome.ignored);
        expect(callStyleMethods(), isNot(contains('cancelIncomingCallStyle')));
        expect(await rememberedCallId(), 'call1');
      });

      test('rings once its notification is gone, though it is still '
          'remembered', () async {
        notifications.active = const [];
        client.resolved = callInvite(callId: 'call1');

        expect(await handle(), IncomingPushOutcome.callRinging);
        expect((callStyle.lastShow.arguments as Map)['callId'], 'call1');
        expect(await rememberedCallId(), 'call1');
      });

      test('a summary for a different call leaves it ringing, but still '
          'remembers that call is over', () async {
        client.resolved = callSummary(
          callId: 'call1',
          status: CallSummaryStatus.ended,
        );

        expect(await handle(), IncomingPushOutcome.ignored);
        expect(callStyleMethods(), isNot(contains('cancelIncomingCallStyle')));
        expect(await rememberedCallId(), ringingCallId);
        expect(await resolvedCallIds(), contains('call1'));
        expect(await resolvedCallIds(), isNot(contains(ringingCallId)));
      });

      test('a summary for a different call still cancels once the ring is '
          'over 45 seconds old', () async {
        await saveRingingCall(await SharedPreferences.getInstance(), (
          roomId: room.id,
          callId: ringingCallId,
          callerId: '@bob:example.org',
          isVideo: false,
        ), now: DateTime.now().subtract(const Duration(seconds: 46)));
        client.resolved = callSummary(
          callId: 'call1',
          status: CallSummaryStatus.ended,
        );

        expect(await handle(), IncomingPushOutcome.ignored);
        expect(callStyleMethods(), contains('cancelIncomingCallStyle'));
      });
    });

    test('a summary cancels the ring and remembers the call is over', () async {
      client.resolved = callSummary(status: CallSummaryStatus.ended);

      expect(await handle(), IncomingPushOutcome.ignored);

      expect(callStyleMethods(), contains('cancelIncomingCallStyle'));
      expect(await resolvedCallIds(), contains('call1'));
    });

    test('a summary for a call that just rang marks it over at once, but '
        'takes its ring down only after the grace', () async {
      await saveRingingCall(await SharedPreferences.getInstance(), (
        roomId: room.id,
        callId: 'call1',
        callerId: '@bob:example.org',
        isVideo: false,
      ));
      client.resolved = callSummary(status: CallSummaryStatus.ended);
      final time = FakeAsync();
      IncomingPushOutcome? outcome;
      time.run((_) {
        handle().then((o) => outcome = o);
      });

      await time.settle();
      expect(await resolvedCallIds(), contains('call1'));
      await time.advance(const Duration(seconds: 2));
      expect(
        callStyleMethods(),
        isNot(contains('cancelIncomingCallStyle')),
        reason: 'the ring just posted is still within its grace window',
      );

      await time.advance(const Duration(seconds: 1));
      expect(outcome, IncomingPushOutcome.ignored);
      expect(
        callStyleMethods(),
        contains('cancelIncomingCallStyle'),
        reason: 'the summary must still take the ring down eventually',
      );
    });

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

    test('shows a plain message quietly when set to mentions only', () async {
      client.resolved = message();

      expect(
        await handle(notifyMe: NotifyMe.mentionsOnly),
        IncomingPushOutcome.message,
      );
      expect(notifications.single.android['channelId'], 'quiet_messages');
    });
  });

  group('an in-room verification request', () {
    Event request({
      String senderId = '@bob:example.org',
      String to = '@me:example.org',
    }) => buildTestEvent(
      room,
      eventId: r'$event',
      senderId: senderId,
      content: {
        'msgtype': 'm.key.verification.request',
        'body': 'Bob is requesting to verify your key',
        'to': to,
        'from_device': 'BOBDEVICE',
        'methods': ['m.sas.v1'],
      },
    );

    test(
      'from someone else is shown, since nothing else would tell you',
      () async {
        client.resolved = request();

        expect(await handle(), IncomingPushOutcome.message);
        expect(notifications.single.title, 'Bob');
        expect(notifications.single.body, 'Wants to verify you');
      },
    );

    test('alerts even when set to mentions only', () async {
      client.resolved = request();

      await handle(notifyMe: NotifyMe.mentionsOnly);

      expect(
        notifications.single.android['channelId'],
        isNot('quiet_messages'),
      );
    });

    test(
      'stays silent when you sent it or it is meant for someone else',
      () async {
        client.resolved = request(senderId: '@me:example.org');
        expect(await handle(), IncomingPushOutcome.ignored);

        client.resolved = request(to: '@carol:example.org');
        expect(await handle(), IncomingPushOutcome.ignored);

        expect(notifications.shown, isEmpty);
      },
    );
  });

  group('an event that stays undecryptable', () {
    Event undecryptable({String senderId = '@bob:example.org'}) =>
        buildTestEvent(
          room,
          eventId: r'$event',
          senderId: senderId,
          type: EventTypes.Encrypted,
          content: {'algorithm': 'm.megolm.v1.aes-sha2', 'ciphertext': 'x'},
        );

    test('keeps a routable "New message" instead of going silent', () async {
      client.resolved = undecryptable();

      expect(await handle(), IncomingPushOutcome.message);
      expect(notifications.single.body, 'Tap to open');
      expect(notifications.single.payload, contains('!room:example.org'));
    });

    test('is quiet when set to mentions only', () async {
      client.resolved = undecryptable();

      expect(
        await handle(notifyMe: NotifyMe.mentionsOnly),
        IncomingPushOutcome.message,
      );
      expect(notifications.single.android['channelId'], 'quiet_messages');
    });

    test('stays silent when you sent it yourself', () async {
      client.resolved = undecryptable(senderId: '@me:example.org');

      expect(await handle(), IncomingPushOutcome.ignored);
      expect(notifications.shown, isEmpty);
    });
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
        await handleIncomingPushNotification(
          client,
          push(),
          notifyMe: NotifyMe.all,
          currentlyOpenRoomId: room.id,
        ),
        IncomingPushOutcome.ignored,
      );
      expect(refusalLine(), contains('room-open'));
      expect(refusalLine(), isNot(contains('own-message')));
    });

    test('says how long ago the message was sent, so a server-side delay '
        'shows up', () async {
      client.resolved = message(
        originServerTs: DateTime.now().subtract(const Duration(minutes: 7)),
      );

      await handle();

      final resolved = lines.singleWhere((l) => l.contains('resolved'));
      expect(resolved, matches(RegExp(r'sent 4[0-9]{2}s ago')));
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
