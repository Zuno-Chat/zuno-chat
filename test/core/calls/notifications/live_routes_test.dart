import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/live_isolate_route.dart';
import 'package:zuno/core/notifications/message_notification_action.dart';

import '../../../helpers/fake_local_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const markRead = (
    kind: MessageNotificationActionKind.markRead,
    roomId: '!room:example.org',
    eventId: r'$1',
    replyText: null,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
  });

  tearDown(() {
    IsolateNameServer.removePortNameMapping(declinePortName);
    IsolateNameServer.removePortNameMapping(messageActionPortName);
  });

  Future<CallNotificationService> app() async {
    final service = CallNotificationService();
    await service.initialize();
    return service;
  }

  Future<CallNotificationService> headless() async {
    final service = CallNotificationService();
    await service.initialize(claimDeclinePort: false);
    return service;
  }

  void strangerTakes(String portName) {
    final stranger = ReceivePort();
    addTearDown(stranger.close);
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(stranger.sendPort, portName);
  }

  group('the decline route', () {
    test('a hold standing down after the app took over leaves the app\'s '
        'route in place', () async {
      final hold = await headless();
      expect(await hold.claimDeclinePortUnlessLive(), isTrue);
      final main = await app();
      expect(hold.stillHoldsDeclinePort(), isFalse);

      hold.releaseDeclinePort();

      expect(main.stillHoldsDeclinePort(), isTrue);
    });

    test('a hold releasing a route it still holds takes it down', () async {
      final hold = await headless();
      await hold.claimDeclinePortUnlessLive();

      hold.releaseDeclinePort();

      expect(IsolateNameServer.lookupPortByName(declinePortName), isNull);
    });

    test('a hold takes over a decline route its isolate left behind when it '
        'went away', () async {
      strangerTakes(declinePortName);
      final hold = await headless();

      expect(
        await hold.claimDeclinePortUnlessLive(
          within: const Duration(milliseconds: 50),
        ),
        isTrue,
      );
      expect(hold.stillHoldsDeclinePort(), isTrue);
    });

    test('a hold leaves a live decline route alone', () async {
      final main = await app();
      final hold = await headless();

      expect(await hold.claimDeclinePortUnlessLive(), isFalse);
      expect(main.stillHoldsDeclinePort(), isTrue);
    });

    test('the app takes its routes back when asked, and only the app '
        'does', () async {
      final main = await app();
      final other = await headless();
      strangerTakes(declinePortName);
      strangerTakes(messageActionPortName);

      other.reclaimLiveRoutes();
      expect(main.stillHoldsDeclinePort(), isFalse);

      main.reclaimLiveRoutes();
      expect(main.stillHoldsDeclinePort(), isTrue);
      expect(await handOffToLiveIsolate(messageActionPortName, {}), isFalse);
    });

    test('a claim asked for after a quiet initialize still claims', () async {
      final main = await headless();

      await main.initialize();

      expect(main.stillHoldsDeclinePort(), isTrue);
    });

    test('an isolate that never claims offers no message action '
        'route', () async {
      await headless();

      expect(IsolateNameServer.lookupPortByName(messageActionPortName), isNull);
    });
  });

  group('handing work to a live isolate', () {
    const decline = {'roomId': '!room:example.org', 'callId': 'call1'};

    test('with no live isolate there is nobody to hand it to', () async {
      expect(await handOffToLiveIsolate(declinePortName, decline), isFalse);
    });

    test('the app takes a decline, and the hand-off lasts until the app is '
        'done with it', () async {
      final main = await app();
      final taken = <HeadlessCallDecline>[];
      final sub = main.onHeadlessDecline.listen(taken.add);
      addTearDown(sub.cancel);
      var settled = false;

      final handed = handOffToLiveIsolate(
        declinePortName,
        decline,
      ).whenComplete(() => settled = true);
      await pumpEventQueue();

      expect(taken.single.roomId, '!room:example.org');
      expect(taken.single.callId, 'call1');
      expect(settled, isFalse);

      taken.single.finished();
      expect(await handed, isTrue);
    });

    test('a decline that reaches the app before anything listens is kept '
        'until something does', () async {
      final main = await app();

      final handed = handOffToLiveIsolate(declinePortName, decline);
      await pumpEventQueue();
      final kept = await main.onHeadlessDecline.first;

      expect(kept.callId, 'call1');
      kept.finished();
      expect(await handed, isTrue);
    });

    test('a decline kept past the time its sender waits is dropped, since '
        'the sender has declined on its own by then', () async {
      final main = await app();
      final handed = handOffToLiveIsolate(
        declinePortName,
        decline,
        doneWithin: const Duration(milliseconds: 50),
      );
      expect(await handed, isFalse);

      main.now = () =>
          DateTime.now().add(liveRouteDoneWithin + const Duration(seconds: 1));
      final taken = <HeadlessCallDecline>[];
      final sub = main.onHeadlessDecline.listen(taken.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(taken, isEmpty);
    });

    test('a decline kept for less than its sender waits is still '
        'handed on', () async {
      final main = await app();
      unawaited(
        handOffToLiveIsolate(
          declinePortName,
          decline,
          doneWithin: const Duration(milliseconds: 50),
        ),
      );
      await pumpEventQueue();

      main.now = () =>
          DateTime.now().add(liveRouteDoneWithin - const Duration(seconds: 1));
      final kept = await main.onHeadlessDecline.first;

      expect(kept.callId, 'call1');
    });

    test('a hold that stopped listening refuses, so the sender declines on '
        'its own', () async {
      final hold = await headless();
      await hold.claimDeclinePortUnlessLive();
      addTearDown(hold.releaseDeclinePort);

      expect(await handOffToLiveIsolate(declinePortName, decline), isFalse);
    });

    test('a route whose isolate is gone costs only a short probe, not the '
        'wait for an answer', () async {
      strangerTakes(declinePortName);
      final clock = Stopwatch()..start();

      expect(await handOffToLiveIsolate(declinePortName, decline), isFalse);

      expect(clock.elapsed, lessThan(liveRouteAcceptWithin));
    });

    test('a live route answers the probe, a gone one does not', () async {
      await app();
      expect(
        await answersPing(IsolateNameServer.lookupPortByName(declinePortName)!),
        isTrue,
      );

      strangerTakes(declinePortName);
      expect(
        await answersPing(
          IsolateNameServer.lookupPortByName(declinePortName)!,
          within: const Duration(milliseconds: 50),
        ),
        isFalse,
      );
    });

    test('a hand-off the app accepted but never finished counts as not done, '
        'so the sender does the work itself', () async {
      final main = await app();
      final sub = main.onHeadlessDecline.listen((_) {});
      addTearDown(sub.cancel);

      expect(
        await handOffToLiveIsolate(
          declinePortName,
          decline,
          doneWithin: const Duration(milliseconds: 50),
        ),
        isFalse,
      );
    });

    test('work that reaches the app too late to be taken is refused, so it '
        'is never done twice', () async {
      final main = await app();
      final taken = <HeadlessCallDecline>[];
      final sub = main.onHeadlessDecline.listen(taken.add);
      addTearDown(sub.cancel);
      final replies = ReceivePort();
      addTearDown(replies.close);

      IsolateNameServer.lookupPortByName(declinePortName)!.send({
        ...decline,
        'replyTo': replies.sendPort,
        'sentAt': DateTime.now()
            .subtract(const Duration(seconds: 10))
            .millisecondsSinceEpoch,
      });

      expect(await replies.first, 'refused');
      expect(taken, isEmpty);
    });

    test('a malformed decline is refused', () async {
      final main = await app();
      final taken = <HeadlessCallDecline>[];
      final sub = main.onHeadlessDecline.listen(taken.add);
      addTearDown(sub.cancel);

      expect(
        await handOffToLiveIsolate(declinePortName, {'roomId': 1}),
        isFalse,
      );
      expect(taken, isEmpty);
    });
  });

  group('the message action route', () {
    test('an app that answers the probe late, but while work sent to it '
        'would still be fresh, takes the work, so no second client sends '
        'it', () async {
      final busyMain = ReceivePort();
      addTearDown(busyMain.close);
      IsolateNameServer.removePortNameMapping(messageActionPortName);
      IsolateNameServer.registerPortWithName(
        busyMain.sendPort,
        messageActionPortName,
      );
      busyMain.listen((message) async {
        if (message is Map && message['ping'] is SendPort) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          answerPing(message);
          return;
        }
        LiveRouteMessage.from(message)!
          ..accept()
          ..finish();
      });

      expect(await handOffToLiveIsolate(messageActionPortName, {}), isTrue);
    });

    test('the app takes an action and the hand-off lasts until it is '
        'done', () async {
      final main = await app();
      final taken = <HandedMessageAction>[];
      final sub = main.onMessageAction.listen(taken.add);
      addTearDown(sub.cancel);

      final handed = handOffToLiveIsolate(
        messageActionPortName,
        encodeMessageAction(markRead, txid: 'zuno-tx-1'),
      );
      await pumpEventQueue();

      expect(taken.single.action, markRead);
      expect(taken.single.txid, 'zuno-tx-1');
      taken.single.finished();
      expect(await handed, isTrue);
    });

    test('an action that arrives before anything listens is kept', () async {
      final main = await app();

      final handed = handOffToLiveIsolate(
        messageActionPortName,
        encodeMessageAction(markRead),
      );
      await pumpEventQueue();
      final kept = await main.onMessageAction.first;

      expect(kept.action, markRead);
      kept.finished();
      expect(await handed, isTrue);
    });

    test('an action kept past the time its sender waits is dropped, since '
        'the sender has done it on its own by then', () async {
      final main = await app();
      expect(
        await handOffToLiveIsolate(
          messageActionPortName,
          encodeMessageAction(markRead),
          doneWithin: const Duration(milliseconds: 50),
        ),
        isFalse,
      );

      main.now = () =>
          DateTime.now().add(liveRouteDoneWithin + const Duration(seconds: 1));
      final taken = <HandedMessageAction>[];
      final sub = main.onMessageAction.listen(taken.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(taken, isEmpty);
    });

    test('something that is not an action is refused', () async {
      await app();

      expect(
        await handOffToLiveIsolate(messageActionPortName, {'kind': 'forward'}),
        isFalse,
      );
    });
  });
}
