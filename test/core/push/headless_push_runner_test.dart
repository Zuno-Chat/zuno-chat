import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/push/headless_push_runner.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/headless_ring.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/notifying_client.dart';
import '../../helpers/push_test_client.dart';

class _MessageClient extends PushTestClient {
  _MessageClient({super.httpClient});

  late final Room room;

  @override
  PushruleEvaluator get pushruleEvaluator => notifyOnMessagesEvaluator();
}

_MessageClient _messageClient({String? avatarUrl, http.Client? httpClient}) {
  final client = _MessageClient(httpClient: httpClient)..setUserId('@me:x');
  final room = client.room = buildTestRoom(client);
  room.setState(
    User('@a:x', displayName: 'Alice', avatarUrl: avatarUrl, room: room),
  );
  client.pushedEvent = (notification) => buildTestEvent(
    room,
    eventId: notification.eventId!,
    senderId: '@a:x',
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
  );
  return client;
}

PushNotification _push({String eventId = '\$abc'}) =>
    PushNotification(eventId: eventId, roomId: '!room:example.org');

HeadlessPushRunner _recordingRunner(
  List<PushTestClient> built, {
  PushTestClient Function() newClient = PushTestClient.new,
}) => HeadlessPushRunner()
  ..clientBuilder = () async {
    final client = newClient();
    built.add(client);
    return client;
  };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordedMethodCalls conversations;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    conversations = installFakeConversationsChannel();
  });

  badgeTests();

  group('the push client', () {
    test('back-to-back pushes share one client', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      await runner.deliver(_push(eventId: r'$one'));
      await runner.deliver(_push(eventId: r'$two'));

      expect(built, hasLength(1));
      expect(built.single.disposeCalls, 0);
    });

    test('a burst shares one client', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      await Future.wait([
        runner.deliver(_push(eventId: r'$one')),
        runner.deliver(_push(eventId: r'$two')),
        runner.deliver(_push(eventId: r'$three')),
      ]);

      expect(built, hasLength(1));
    });

    test('is kept after its push, however long nothing else comes', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);

        unawaited(runner.deliver(_push()));
        async.elapse(const Duration(hours: 1));

        expect(built.single.disposeCalls, 0);
        expect(runner.quiescent, isFalse);
      });
    });

    test('a push after the client was given up opens a fresh one', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      await runner.deliver(_push(eventId: r'$one'));
      runner.yieldClient();
      await pumpEventQueue();
      await runner.deliver(_push(eventId: r'$two'));

      expect(built, hasLength(2));
      expect(built.first.disposeCalls, 1);
      expect(built.last.disposeCalls, 0);
    });

    test('a client held for a long time is still reused once free', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);
        final refining = Completer<void>();

        unawaited(
          runner.withClient(
            (_) async => runner.keepClientWhile(refining.future),
          ),
        );
        async.elapse(const Duration(minutes: 2));
        refining.complete();
        async.flushMicrotasks();
        unawaited(runner.deliver(_push()));
        async.flushMicrotasks();

        expect(built, hasLength(1));
        expect(built.single.disposeCalls, 0);
      });
    });

    test('tells the caller once for each client it opens', () async {
      final opened = <Client>[];
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built)..onClientOpened = opened.add;

      await runner.deliver(_push(eventId: r'$one'));
      await runner.deliver(_push(eventId: r'$two'));
      runner.yieldClient();
      await pumpEventQueue();
      await runner.deliver(_push(eventId: r'$three'));

      expect(opened, [built.first, built.last]);
    });

    test(
      'a caller that fails on a new client does not break the push',
      () async {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built)
          ..onClientOpened = (_) => throw StateError('no prefs');

        await runner.deliver(_push());

        expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
        expect(built, hasLength(1));
      },
    );

    test('a client held through a long ring keeps serving', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);
        final ringing = Completer<void>();
        Client? declinedWith;

        unawaited(
          runner.withClient(
            (_) async => runner.keepClientWhile(ringing.future),
          ),
        );
        async.elapse(const Duration(seconds: 35));
        unawaited(runner.withClient((client) async => declinedWith = client));
        async.flushMicrotasks();

        expect(built, hasLength(1));
        expect(declinedWith, same(built.single));
        ringing.complete();
      });
    });

    test('never opens a fresh client while the old one is closing', () {
      fakeAsync((async) {
        final closing = Completer<void>();
        final built = <PushTestClient>[];
        final runner = HeadlessPushRunner()
          ..clientBuilder = () async {
            final client = PushTestClient(
              disposing: built.isEmpty ? closing.future : null,
            );
            built.add(client);
            return client;
          };

        unawaited(runner.deliver(_push(eventId: r'$one')));
        async.flushMicrotasks();
        runner.yieldClient();
        async.flushMicrotasks();
        unawaited(runner.deliver(_push(eventId: r'$two')));
        async.flushMicrotasks();
        expect(built, hasLength(1));

        closing.complete();
        async.flushMicrotasks();
        expect(built, hasLength(2));
      });
    });

    test('the ack never waits for the client to be let go', () async {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async =>
            PushTestClient(disposing: Completer<void>().future);

      await runner
          .deliver(_push())
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('the ack waited for the client to close'),
          );
    });

    test('nor for a prepared client no push needed', () async {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async =>
            PushTestClient(disposing: Completer<void>().future);

      runner.prepareClient();
      await pumpEventQueue();
      await runner
          .deliver(
            const PushNotification(counts: PushNotificationCounts(unread: 2)),
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('the ack waited for the prepared client'),
          );
    });
  });

  group('prepareClient', () {
    test('starts the build ahead of the push and the push reuses it', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      runner.prepareClient();
      await pumpEventQueue();
      expect(built, hasLength(1));

      await runner.deliver(_push());

      expect(built, hasLength(1));
    });

    test('is a no-op when a build is in flight or a client is live', () async {
      var builds = 0;
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          builds++;
          return PushTestClient();
        };

      runner.prepareClient();
      runner.prepareClient();
      await pumpEventQueue();
      expect(builds, 1);

      final live = HeadlessPushRunner()
        ..liveClient = PushTestClient()
        ..clientBuilder = () async {
          builds++;
          return PushTestClient();
        };
      live.prepareClient();
      await pumpEventQueue();
      expect(builds, 1);
    });

    test('a prepared client nobody needed is kept until it is settled', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);

        runner.prepareClient();
        unawaited(
          runner.deliver(
            const PushNotification(counts: PushNotificationCounts(unread: 3)),
          ),
        );
        async.elapse(const Duration(minutes: 10));
        expect(built.single.disposeCalls, 0);

        unawaited(runner.settle());
        async.flushMicrotasks();
        expect(built.single.disposeCalls, 1);
      });
    });

    test('a prepared build that fails surfaces in the push, and the next '
        'push builds again', () async {
      var builds = 0;
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          builds++;
          if (builds == 1) throw StateError('no database');
          return PushTestClient();
        };

      runner.prepareClient();
      await pumpEventQueue();
      await runner.deliver(_push(eventId: r'$one'));
      expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);

      await runner.deliver(_push(eventId: r'$two'));
      expect(builds, 2);
    });
  });

  group('prepareHeadlessPush', () {
    test('sets up notifications and reports it ready', () async {
      var setups = 0;

      final ready = await prepareHeadlessPush(
        initializeNotifications: () async => setups++,
      );

      expect(ready, isTrue);
      expect(setups, 1);
    });

    test('a failed setup reports false', () async {
      final ready = await prepareHeadlessPush(
        initializeNotifications: () async => throw StateError('no channel'),
      );

      expect(ready, isFalse);
    });
  });

  group('when the app asks for the client', () {
    test('an idle client is let go at once', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);
      await runner.deliver(_push());

      runner.yieldClient();
      await pumpEventQueue();

      expect(built.single.disposeCalls, 1);
      expect(built.single.closedDatabase, isFalse);
      expect(runner.quiescent, isTrue);
    });

    test(
      'a push being handled finishes first, then the client is let go',
      () async {
        final fetching = Completer<void>();
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);
        final running = runner.withClient((_) => fetching.future);
        await pumpEventQueue();

        runner.yieldClient();
        await pumpEventQueue();
        expect(built.single.disposeCalls, 0);

        fetching.complete();
        await running;
        await pumpEventQueue();
        expect(built.single.disposeCalls, 1);
      },
    );

    test(
      'pushes already waiting are handled before the client is let go',
      () async {
        final first = Completer<void>();
        final served = <String>[];
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);
        final one = runner.withClient((_) => first.future);
        final two = runner.withClient((_) async => served.add('two'));
        await pumpEventQueue();

        runner.yieldClient();
        first.complete();
        await Future.wait([one, two]);
        await pumpEventQueue();

        expect(served, ['two']);
        expect(built, hasLength(1));
        expect(built.single.disposeCalls, 1);
      },
    );

    test(
      'a push still deciding whether it needs the client keeps it',
      () async {
        final asking = Completer<bool>();
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built)
          ..isAppSyncing = (() => true)
          ..nativeAppInFront = () => asking.future;
        runner.prepareClient();
        await pumpEventQueue();
        final delivery = runner.deliver(_push());
        await pumpEventQueue();

        runner.yieldClient();
        await pumpEventQueue();
        expect(built.single.disposeCalls, 0);

        asking.complete(false);
        await delivery;
        await pumpEventQueue();
        expect(built.single.disposeCalls, 1);
      },
    );

    test(
      'a client still being opened is let go as soon as it is ready',
      () async {
        final build = Completer<Client>();
        final runner = HeadlessPushRunner()..clientBuilder = () => build.future;
        runner.prepareClient();

        runner.yieldClient();
        final client = PushTestClient();
        build.complete(client);
        await pumpEventQueue();

        expect(client.disposeCalls, 1);
        expect(runner.quiescent, isTrue);
      },
    );

    test('a yield that lands while a build fails does not cut the next '
        'client short', () async {
      var builds = 0;
      final failing = Completer<Client>();
      final built = <PushTestClient>[];
      final runner = HeadlessPushRunner()
        ..clientBuilder = () {
          builds++;
          if (builds == 1) return failing.future;
          final client = PushTestClient();
          built.add(client);
          return Future.value(client);
        };
      final first = runner.deliver(_push(eventId: r'$one'));
      await pumpEventQueue();

      runner.yieldClient();
      failing.completeError(StateError('database locked'));
      await first;
      await runner.deliver(_push(eventId: r'$two'));
      await pumpEventQueue();

      expect(built.single.disposeCalls, 0);
    });

    test('with no client to give up, nothing changes', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      runner.yieldClient();
      await runner.deliver(_push());
      await pumpEventQueue();

      expect(built.single.disposeCalls, 0);
    });

    test('never lets go of a live client it was handed', () async {
      final live = PushTestClient();
      final runner = HeadlessPushRunner()..liveClient = live;
      await runner.deliver(_push());

      runner.yieldClient();
      await pumpEventQueue();

      expect(live.disposeCalls, 0);
    });

    test('follows the lease\'s yield requests', () async {
      final requests = StreamController<void>.broadcast();
      addTearDown(requests.close);
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);
      final sub = runner.yieldWhenAsked(requests.stream);
      addTearDown(sub.cancel);
      await runner.deliver(_push());

      requests.add(null);
      await pumpEventQueue();

      expect(built.single.disposeCalls, 1);
    });
  });

  group('a push the store is not free for', () {
    test('is left to its notice, and the next push still runs', () async {
      var builds = 0;
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          builds++;
          if (builds == 1) throw const ClientLeaseDenied();
          return PushTestClient();
        };

      await runner.deliver(_push(eventId: r'$one'));
      expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
      expect(conversations.named('takePushNotice'), isEmpty);

      await runner.deliver(_push(eventId: r'$two'));
      expect(builds, 2);
    });

    test('reports no outcome to the caller', () async {
      IncomingPushOutcome? reported;
      final runner = HeadlessPushRunner()
        ..clientBuilder = (() async => throw const ClientLeaseDenied())
        ..onPushHandled = (outcome) async => reported = outcome;

      await runner.deliver(_push());

      expect(reported, isNull);
      expect(runner.quiescent, isTrue);
    });
  });

  group('with an idle limit', () {
    test('lets an idle client go once the limit passes', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built)
          ..idleLimit = const Duration(minutes: 10);

        unawaited(runner.deliver(_push()));
        async.elapse(const Duration(minutes: 9));
        expect(built.single.disposeCalls, 0);

        async.elapse(const Duration(minutes: 1));
        expect(built.single.disposeCalls, 1);
        expect(runner.quiescent, isTrue);
      });
    });

    test('a push in between starts the wait again', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built)
          ..idleLimit = const Duration(minutes: 10);

        unawaited(runner.deliver(_push(eventId: r'$one')));
        async.elapse(const Duration(minutes: 9));
        unawaited(runner.deliver(_push(eventId: r'$two')));
        async.elapse(const Duration(minutes: 9));
        expect(built.single.disposeCalls, 0);

        async.elapse(const Duration(minutes: 1));
        expect(built, hasLength(1));
        expect(built.single.disposeCalls, 1);
      });
    });

    test('never lets go while work holds the client', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final refining = Completer<void>();
        final runner = _recordingRunner(built)
          ..idleLimit = const Duration(minutes: 10);

        unawaited(
          runner.withClient(
            (_) async => runner.keepClientWhile(refining.future),
          ),
        );
        async.elapse(const Duration(minutes: 30));
        expect(built.single.disposeCalls, 0);

        refining.complete();
        async.elapse(const Duration(minutes: 10));
        expect(built.single.disposeCalls, 1);
      });
    });
  });

  test('runs onPushHandled outside the queue, so a ring hold does not '
      'block the push that would cancel it', () async {
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async => PushTestClient();
    final holdReleased = Completer<void>();
    var handledCount = 0;

    runner.onPushHandled = (_) async {
      handledCount++;
      if (handledCount == 1) await holdReleased.future;
    };

    final first = runner.deliver(_push(eventId: '\$ring'));
    await runner
        .deliver(_push(eventId: '\$hangup'))
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('the ring hold blocked the next push'),
        );

    expect(handledCount, 2);
    holdReleased.complete();
    await first;
  });

  test('onPushHandled runs once the push is done with its client, so a '
      'decline from it reuses that client', () async {
    final built = <PushTestClient>[];
    final runner = _recordingRunner(built);
    final handled = <IncomingPushOutcome>[];
    Client? declinedWith;
    runner.onPushHandled = (outcome) async {
      handled.add(outcome);
      declinedWith = await runner.withClient((client) async => client);
    };

    await runner.deliver(_push());

    expect(handled, [IncomingPushOutcome.ignored]);
    expect(built, hasLength(1));
    expect(declinedWith, same(built.single));
  });

  test('a throwing push does not poison the queue for the next one', () async {
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        if (builds == 1) throw StateError('database locked');
        return PushTestClient();
      };

    await runner.deliver(_push(eventId: '\$bad'));
    await runner.deliver(_push(eventId: '\$good'));

    expect(builds, 2);
  });

  test(
    'withClient refreshes an expiring token before the action runs',
    () async {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async =>
            ExpiringTokenClient()..accessToken = 'stale';

      expect(
        await runner.withClient((client) async => client.accessToken),
        'fresh',
      );
    },
  );

  test('withClient refreshes a live client too', () async {
    final runner = HeadlessPushRunner()
      ..liveClient = (ExpiringTokenClient()..accessToken = 'stale');

    expect(
      await runner.withClient((client) async => client.accessToken),
      'fresh',
    );
  });

  test('a token refresh that stalls holds each action up only so long', () {
    fakeAsync((async) {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => ExpiringTokenClient(refreshStalls: true);
      final ran = <String>[];

      unawaited(runner.withClient((_) async => ran.add('first')));
      unawaited(runner.withClient((_) async => ran.add('second')));
      async.elapse(freshTokenBound - const Duration(milliseconds: 1));
      expect(ran, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect(ran, ['first']);

      async.elapse(freshTokenBound);
      expect(ran, ['first', 'second']);
    });
  });

  test('withClient returns null when there is no client to be had', () async {
    final runner = HeadlessPushRunner();
    expect(await runner.withClient((_) async => 'ran'), isNull);
  });

  test('lastPushOutcome resets per push rather than keeping the previous '
      'answer standing', () async {
    final runner = HeadlessPushRunner();
    runner.lastPushOutcome = IncomingPushOutcome.callRinging;

    await runner.deliver(_push());

    expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
  });

  test('hands the open room to the handler, so a push for the room on '
      'screen stays silent', () async {
    final notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    final client = _messageClient();
    final runner = HeadlessPushRunner()
      ..liveClient = client
      ..currentlyOpenRoomId = () => client.room.id;

    await runner.deliver(_push());

    expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
    expect(notifications.shown, isEmpty);
  });

  group('while the app is resumed and syncing', () {
    test('a push the native side saw with the app not in front is still '
        'handled, as when a ring shows over the lock screen', () async {
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      final runner = HeadlessPushRunner()
        ..liveClient = _messageClient()
        ..isAppSyncing = () => true;

      await runner.deliver(_push(), appInFront: false);

      expect(runner.lastPushOutcome, IncomingPushOutcome.message);
      expect(notifications.shown, hasLength(1));
    });

    test('a push the native side saw in front is left to the sync '
        'path', () async {
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      final runner = HeadlessPushRunner()
        ..liveClient = _messageClient()
        ..isAppSyncing = () => true;

      await runner.deliver(_push(), appInFront: true);

      expect(notifications.shown, isEmpty);
      expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
    });

    test('without a verdict in the push, asks the native side', () async {
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      var asked = 0;
      var inFront = false;
      final runner = HeadlessPushRunner()
        ..liveClient = _messageClient()
        ..isAppSyncing = (() => true)
        ..nativeAppInFront = () async {
          asked++;
          return inFront;
        };

      await runner.deliver(_push(eventId: r'$one'));
      expect(notifications.shown, hasLength(1));

      inFront = true;
      await runner.deliver(_push(eventId: r'$two'));
      expect(notifications.shown, hasLength(1));
      expect(asked, 2);
    });

    test('never asks the native side while the app is not syncing', () async {
      installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      var asked = 0;
      final runner = HeadlessPushRunner()
        ..liveClient = _messageClient()
        ..nativeAppInFront = () async {
          asked++;
          return true;
        };

      await runner.deliver(_push());

      expect(asked, 0);
    });
  });

  group('a signed-out client', () {
    test('never fetches or posts anything', () async {
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      final client = _messageClient()..signedIn = false;
      final runner = HeadlessPushRunner()..liveClient = client;

      await runner.deliver(_push());

      expect(client.fetched, isEmpty);
      expect(notifications.shown, isEmpty);
      expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
    });

    test('takes back the instant notice the push put up', () async {
      final client = _messageClient()..signedIn = false;
      final runner = HeadlessPushRunner()..liveClient = client;

      await runner.deliver(_push(eventId: r'$abc'));

      expect(conversations.named('takePushNotice').map((c) => c.arguments), [
        {'roomId': '!room:example.org', 'eventId': r'$abc'},
      ]);
    });
  });

  group('a push that rings', () {
    setUp(installHeadlessRingChannels);

    HeadlessPushRunner ringingRunner(List<PushTestClient> built) =>
        _recordingRunner(built, newClient: ringingPushClient);

    test('keeps its client through the ring without holding up the ack', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final ringOver = Completer<void>();
        var holds = 0;
        final runner = ringingRunner(built)
          ..onRinging = () {
            holds++;
            return ringOver.future;
          };
        var acked = false;
        Client? declinedWith;

        unawaited(
          runner.deliver(_push(eventId: r'$invite')).then((_) => acked = true),
        );
        async.flushMicrotasks();
        expect(acked, isTrue);
        expect(runner.lastPushOutcome, IncomingPushOutcome.callRinging);
        expect(holds, 1);

        async.elapse(const Duration(seconds: 20));
        unawaited(runner.withClient((client) async => declinedWith = client));
        async.flushMicrotasks();
        expect(built, hasLength(1));
        expect(declinedWith, same(built.single));
        expect(built.single.disposeCalls, 0);
        expect(runner.quiescent, isFalse);

        ringOver.complete();
        async.flushMicrotasks();
        expect(built.single.disposeCalls, 0);
        unawaited(runner.settle());
        async.flushMicrotasks();
        expect(built.single.disposeCalls, 1);
        expect(runner.quiescent, isTrue);
      });
    });

    test('gives its client up at once when the app asks for it, and the '
        'engine stays busy until the ring ends', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final ringOver = Completer<void>();
        final runner = ringingRunner(built)..onRinging = () => ringOver.future;

        unawaited(runner.deliver(_push(eventId: r'$invite')));
        async.flushMicrotasks();
        expect(runner.lastPushOutcome, IncomingPushOutcome.callRinging);

        runner.yieldClient();
        async.flushMicrotasks();
        expect(built.single.disposeCalls, 1);
        expect(runner.quiescent, isFalse);

        ringOver.complete();
        async.flushMicrotasks();
        expect(runner.quiescent, isTrue);
      });
    });

    test('a ring the caller waits out after the push does not keep the '
        'client from the app', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final ringOver = Completer<void>();
        final runner = ringingRunner(built)
          ..onPushHandled = (outcome) async {
            if (outcome == IncomingPushOutcome.callRinging) {
              await ringOver.future;
            }
          };
        var delivered = false;

        unawaited(
          runner
              .deliver(_push(eventId: r'$invite'))
              .then((_) => delivered = true),
        );
        async.flushMicrotasks();
        expect(delivered, isFalse);

        runner.yieldClient();
        async.flushMicrotasks();
        expect(built.single.disposeCalls, 1);
        expect(runner.quiescent, isFalse);

        ringOver.complete();
        async.flushMicrotasks();
        expect(delivered, isTrue);
        expect(runner.quiescent, isTrue);
      });
    });

    test('a push that does not ring starts no hold', () async {
      var holds = 0;
      final runner = HeadlessPushRunner()
        ..liveClient = _messageClient()
        ..onRinging = () {
          holds++;
          return null;
        };

      await runner.deliver(_push());

      expect(runner.lastPushOutcome, IncomingPushOutcome.message);
      expect(holds, 0);
    });
  });

  group('a notification still refining', () {
    test('keeps a short wake lock of its own until it settles', () async {
      installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      final locks = recordMethodChannel('zuno/wake_lock');
      final avatarFetch = Completer<void>();
      final client = _messageClient(
        avatarUrl: 'mxc://x/alice',
        httpClient: MockClient((_) async {
          await avatarFetch.future;
          return http.Response('', 404);
        }),
      )..accessToken = 'token';
      final runner = HeadlessPushRunner()..liveClient = client;

      await runner.deliver(_push());

      expect(runner.lastPushOutcome, IncomingPushOutcome.message);
      expect(locks.methods, ['acquire']);

      avatarFetch.complete();
      await pumpEventQueue();

      expect(locks.methods, ['acquire', 'release']);
    });
  });

  group('quiescent', () {
    test('is false while a push is being delivered', () async {
      final fetching = Completer<void>();
      final runner = HeadlessPushRunner()
        ..clientBuilder = (() async => PushTestClient())
        ..isAppSyncing = (() => true)
        ..nativeAppInFront = () async {
          await fetching.future;
          return false;
        };

      final delivery = runner.deliver(_push());
      await pumpEventQueue();
      expect(runner.quiescent, isFalse);

      fetching.complete();
      await delivery;
      await runner.settle();
      expect(runner.quiescent, isTrue);
    });

    test('is false while the client is kept, and while it is let go', () {
      fakeAsync((async) {
        final closing = Completer<void>();
        final runner = HeadlessPushRunner()
          ..clientBuilder = () async =>
              PushTestClient(disposing: closing.future);

        unawaited(runner.deliver(_push()));
        async.flushMicrotasks();
        expect(runner.quiescent, isFalse);

        runner.yieldClient();
        async.flushMicrotasks();
        expect(runner.quiescent, isFalse);

        closing.complete();
        async.flushMicrotasks();
        expect(runner.quiescent, isTrue);
      });
    });

    test('is false while a prepared client is waiting', () async {
      final build = Completer<Client>();
      final runner = HeadlessPushRunner()..clientBuilder = () => build.future;

      runner.prepareClient();
      expect(runner.quiescent, isFalse);
      build.complete(PushTestClient());
    });
  });

  group('settle', () {
    test('is quiet at once for a runner that never opened a client', () async {
      expect(await HeadlessPushRunner().settle(), isTrue);
    });

    test('lets go of a kept client at once and reports quiet', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);
      await runner.deliver(_push());

      expect(await runner.settle(), isTrue);
      expect(built.single.disposeCalls, 1);
      expect(runner.quiescent, isTrue);
    });

    test('lets go of a prepared client no push used', () async {
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      runner.prepareClient();

      expect(await runner.settle(), isTrue);
      expect(built.single.disposeCalls, 1);
    });

    test('answers only once the client has been let go', () async {
      final closing = Completer<void>();
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => PushTestClient(disposing: closing.future);
      await runner.deliver(_push());

      bool? answer;
      final settling = runner.settle().then((quiet) => answer = quiet);
      await pumpEventQueue();
      expect(answer, isNull);

      closing.complete();
      await settling;
      expect(answer, isTrue);
    });

    test('reports busy and keeps the client while a push runs', () async {
      final fetching = Completer<void>();
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);

      final running = runner.withClient((_) => fetching.future);
      await pumpEventQueue();

      expect(await runner.settle(), isFalse);
      expect(built.single.disposeCalls, 0);
      fetching.complete();
      await running;
    });

    test('reports busy while work holds the client', () async {
      final refining = Completer<void>();
      final built = <PushTestClient>[];
      final runner = _recordingRunner(built);
      await runner.withClient(
        (_) async => runner.keepClientWhile(refining.future),
      );

      expect(await runner.settle(), isFalse);
      expect(built.single.disposeCalls, 0);

      refining.complete();
      await pumpEventQueue();
      expect(await runner.settle(), isTrue);
      expect(built.single.disposeCalls, 1);
    });

    test('reports busy while a push is still being delivered', () async {
      final asking = Completer<bool>();
      final runner = HeadlessPushRunner()
        ..clientBuilder = (() async => PushTestClient())
        ..isAppSyncing = (() => true)
        ..nativeAppInFront = () => asking.future;

      final delivery = runner.deliver(_push());
      await pumpEventQueue();

      expect(await runner.settle(), isFalse);
      asking.complete(false);
      await delivery;
    });
  });

  group('keepClientWhile', () {
    test('holds the burst client through a yield until the work ends', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);
        final refining = Completer<void>();

        unawaited(
          runner.withClient(
            (_) async => runner.keepClientWhile(refining.future),
          ),
        );
        async.flushMicrotasks();
        runner.yieldClient();
        async.elapse(const Duration(minutes: 1));
        expect(built.single.disposeCalls, 0);

        refining.complete();
        async.flushMicrotasks();
        expect(built.single.disposeCalls, 1);
      });
    });

    test('failed work still lets the client go', () {
      fakeAsync((async) {
        final built = <PushTestClient>[];
        final runner = _recordingRunner(built);
        final refining = Completer<void>();

        unawaited(
          runner.withClient(
            (_) async => runner.keepClientWhile(refining.future),
          ),
        );
        async.flushMicrotasks();
        runner.yieldClient();
        refining.completeError(StateError('offline'));
        async.flushMicrotasks();

        expect(built.single.disposeCalls, 1);
      });
    });

    test('never disposes a live client', () async {
      final live = PushTestClient();
      final runner = HeadlessPushRunner()..liveClient = live;

      await runner.withClient((client) async {
        runner.keepClientWhile(Future<void>.value());
      });
      await runner.settle();

      expect(live.disposeCalls, 0);
    });
  });
}

void badgeTests() {
  group('badge-only pushes', () {
    late RecordedNotifications notifications;
    var builds = 0;
    late HeadlessPushRunner runner;

    setUp(() {
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      builds = 0;
      runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          builds++;
          return PushTestClient();
        };
      notifications.active = [
        {'id': 11, 'channelId': 'direct_messages', 'payload': '{}'},
        {'id': 22, 'channelId': 'group_messages', 'payload': '{}'},
        {'id': 4002, 'channelId': 'calls_ringing', 'payload': '{}'},
      ];
    });

    test(
      'unread 0 clears the message notifications without opening a client',
      () async {
        await runner.deliver(
          const PushNotification(counts: PushNotificationCounts(unread: 0)),
        );

        expect(builds, 0);
        expect(notifications.cancelled, containsAll([11, 22]));
        expect(notifications.cancelled, isNot(contains(4002)));
        expect(runner.lastPushOutcome, IncomingPushOutcome.badge);
      },
    );

    test('a non-zero badge is ignored, still without a client', () async {
      await runner.deliver(
        const PushNotification(counts: PushNotificationCounts(unread: 2)),
      );

      expect(builds, 0);
      expect(notifications.cancelled, isEmpty);
    });

    test('a badge push still reports back to the caller, so a headless '
        'wakelock is released', () async {
      IncomingPushOutcome? reported;
      runner.onPushHandled = (outcome) async => reported = outcome;

      await runner.deliver(
        const PushNotification(counts: PushNotificationCounts(unread: 0)),
      );

      expect(reported, IncomingPushOutcome.badge);
    });
  });
}
