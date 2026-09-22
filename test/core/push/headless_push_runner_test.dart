import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/headless_push_runner.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient({this.onDispose})
    : super('test', database: FakeDatabaseApi());

  int disposeCalls = 0;
  bool? closedDatabase;

  final void Function()? onDispose;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async => null;

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposeCalls++;
    closedDatabase = closeDatabase;
    onDispose?.call();
  }
}

class _ExpiringClient extends Client {
  _ExpiringClient()
    : super(
        'test',
        database: FakeDatabaseApi(),
        onSoftLogout: (client) async => client.accessToken = 'fresh',
      );

  @override
  DateTime? get accessTokenExpiresAt =>
      DateTime.now().add(const Duration(seconds: 30));

  @override
  Future<void> dispose({bool closeDatabase = true}) async {}
}

class _MessageClient extends Client {
  _MessageClient() : super('test', database: FakeDatabaseApi());

  late Room room;

  @override
  PushruleEvaluator get pushruleEvaluator => PushruleEvaluator.fromRuleset(
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
  }) async => buildTestEvent(
    room,
    eventId: notification.eventId!,
    senderId: '@a:x',
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
  );
}

_MessageClient _messageClient() {
  final client = _MessageClient()..setUserId('@me:x');
  client.room = buildTestRoom(client);
  client.room.setState(User('@a:x', displayName: 'Alice', room: client.room));
  return client;
}

PushNotification _push({String eventId = '\$abc'}) =>
    PushNotification(eventId: eventId, roomId: '!room:example.org');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  badgeTests();

  test('builds one client per push when pushes arrive one at a time', () async {
    final built = <_RecordingClient>[];
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        final client = _RecordingClient();
        built.add(client);
        return client;
      };

    await runner.deliver(_push(eventId: '\$one'));
    await runner.deliver(_push(eventId: '\$two'));

    expect(built, hasLength(2));
    expect(built.every((c) => c.disposeCalls == 1), isTrue);
    expect(built.every((c) => c.closedDatabase == false), isTrue);
  });

  test('keeps one client for a burst and disposes it once the queue '
      'drains', () async {
    final built = <_RecordingClient>[];
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        final client = _RecordingClient();
        built.add(client);
        return client;
      };

    await Future.wait([
      runner.deliver(_push(eventId: '\$one')),
      runner.deliver(_push(eventId: '\$two')),
      runner.deliver(_push(eventId: '\$three')),
    ]);

    expect(built, hasLength(1));
    expect(built.single.disposeCalls, 1);
  });

  group('prepareClient', () {
    test('starts the build ahead of the push and the push reuses it', () async {
      final built = <_RecordingClient>[];
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          final client = _RecordingClient();
          built.add(client);
          return client;
        };

      runner.prepareClient();
      await pumpEventQueue();
      expect(built, hasLength(1));

      await runner.deliver(_push());

      expect(built, hasLength(1));
      expect(built.single.disposeCalls, 1);
    });

    test('is a no-op when a build is in flight or a client is live', () async {
      var builds = 0;
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          builds++;
          return _RecordingClient();
        };

      runner.prepareClient();
      runner.prepareClient();
      await pumpEventQueue();
      expect(builds, 1);

      final live = HeadlessPushRunner()
        ..liveClient = _RecordingClient()
        ..clientBuilder = () async {
          builds++;
          return _RecordingClient();
        };
      live.prepareClient();
      await pumpEventQueue();
      expect(builds, 1);
    });

    test('a prepared client nobody needed is disposed once the push is '
        'done', () async {
      final built = <_RecordingClient>[];
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          final client = _RecordingClient();
          built.add(client);
          return client;
        };

      runner.prepareClient();
      await runner.deliver(
        PushNotification(
          roomId: '!room:example.org',
          counts: PushNotificationCounts(unread: 3),
        ),
      );

      expect(built, hasLength(1));
      expect(built.single.disposeCalls, 1);
    });

    test('a prepared build that fails surfaces in the push, not as an '
        'unhandled error', () async {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => throw StateError('no database');

      runner.prepareClient();
      await pumpEventQueue();
      await runner.deliver(_push());

      expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
    });
  });

  group('prepareHeadlessPush', () {
    test(
      'starts the client build before the notification setup finishes',
      () async {
        final setup = Completer<void>();
        var builds = 0;
        final runner = HeadlessPushRunner()
          ..clientBuilder = () async {
            builds++;
            return _RecordingClient();
          };

        final ready = prepareHeadlessPush(
          runner,
          initializeNotifications: () => setup.future,
        );
        await pumpEventQueue();
        final buildsBeforeSetupFinished = builds;
        setup.complete();

        expect(await ready, isTrue);
        expect(buildsBeforeSetupFinished, 1);
      },
    );

    test('a failed setup reports false', () async {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => _RecordingClient();

      final ready = await prepareHeadlessPush(
        runner,
        initializeNotifications: () async => throw StateError('no channel'),
      );

      expect(ready, isFalse);
    });
  });

  test('never disposes a live client it was handed', () async {
    final client = _RecordingClient();
    final runner = HeadlessPushRunner()..liveClient = client;

    await runner.deliver(_push());

    expect(client.disposeCalls, 0);
  });

  test(
    'serializes concurrent deliveries so two clients never overlap',
    () async {
      var open = 0;
      var maxOpen = 0;
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          open++;
          maxOpen = open > maxOpen ? open : maxOpen;
          return _RecordingClient(onDispose: () => open--);
        };

      await Future.wait([
        runner.deliver(_push(eventId: '\$one')),
        runner.deliver(_push(eventId: '\$two')),
      ]);

      expect(maxOpen, 1);
    },
  );

  test('runs onPushHandled outside the queue, so a ring hold does not '
      'block the push that would cancel it', () async {
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async => _RecordingClient();
    final holdReleased = Completer<void>();
    var secondDelivered = false;
    var handledCount = 0;

    runner.onPushHandled = (_) async {
      handledCount++;
      if (handledCount == 1) await holdReleased.future;
    };

    final first = runner.deliver(_push(eventId: '\$ring'));
    await runner.deliver(_push(eventId: '\$hangup'));
    secondDelivered = true;

    expect(secondDelivered, isTrue);
    holdReleased.complete();
    await first;
  });

  test('a throwing push does not poison the queue for the next one', () async {
    var builds = 0;
    final runner = HeadlessPushRunner()
      ..clientBuilder = () async {
        builds++;
        if (builds == 1) throw StateError('database locked');
        return _RecordingClient();
      };

    await runner.deliver(_push(eventId: '\$bad'));
    await runner.deliver(_push(eventId: '\$good'));

    expect(builds, 2);
  });

  test(
    'withClient refreshes an expiring token before the action runs',
    () async {
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async => _ExpiringClient()..accessToken = 'stale';

      expect(
        await runner.withClient((client) async => client.accessToken),
        'fresh',
      );
    },
  );

  test('withClient refreshes a live client too', () async {
    final runner = HeadlessPushRunner()
      ..liveClient = (_ExpiringClient()..accessToken = 'stale');

    expect(
      await runner.withClient((client) async => client.accessToken),
      'fresh',
    );
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

  test('drops a push while the app is in front and syncing, leaving the '
      'message to the sync path', () async {
    final notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    final client = _messageClient();
    final runner = HeadlessPushRunner()
      ..liveClient = client
      ..isAppSyncing = () => true;

    await runner.deliver(_push());

    expect(notifications.shown, isEmpty);
    expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
  });

  test(
    'notifies when no room is open, which is the headless default',
    () async {
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      final client = _messageClient();
      final runner = HeadlessPushRunner()..liveClient = client;

      await runner.deliver(_push());

      expect(runner.lastPushOutcome, IncomingPushOutcome.message);
      expect(notifications.shown, hasLength(1));
    },
  );
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
          return _RecordingClient();
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
