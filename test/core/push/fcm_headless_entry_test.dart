import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart'
    show fcmPendingTokenKey;
import 'package:zuno/core/push/fcm_headless_entry.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/fcm_registration_store.dart';
import 'package:zuno/core/push/headless_push_runner.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient({this.onDispose, this.postFails = false})
    : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  final void Function()? onDispose;
  final bool postFails;
  final fetched = <String?>[];
  final posted = <Pusher>[];
  final deleted = <PusherId>[];
  int disposeCalls = 0;

  @override
  bool isLogged() => true;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    fetched.add(notification.eventId);
    return null;
  }

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {
    if (postFails) throw StateError('homeserver unreachable');
    posted.add(pusher);
  }

  @override
  Future<void> deletePusher(PusherId pusherId) async => deleted.add(pusherId);

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    disposeCalls++;
    onDispose?.call();
  }
}

class _RingingClient extends Client {
  _RingingClient() : super('test', database: FakeDatabaseApi()) {
    setUserId('@me:example.org');
  }

  @override
  bool isLogged() => true;

  @override
  Future<Event?> getEventByPushNotification(
    PushNotification notification, {
    bool storeInDatabase = true,
    Duration timeoutForServerRequests = const Duration(seconds: 8),
    bool returnNullIfSeen = true,
  }) async {
    final room = buildTestRoom(this);
    return buildTestEvent(
      room,
      eventId: r'$invite',
      senderId: '@bob:example.org',
      originServerTs: DateTime.now(),
      content: const {
        'msgtype': 'im.zuno.call_invite',
        'call_id': 'call1',
        'kind': 'voice',
        'body': 'Incoming call',
      },
    );
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/fcm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  late Future<Object?> Function() readyAnswer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetFcmBackgroundRunnerForTesting();
    calls.clear();
    readyAnswer = () async => true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'ready' ? readyAnswer() : null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  void installRingChannels() {
    ringRateLimiter.clear();
    installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    for (final name in ['zuno/calls', 'zuno/vibration']) {
      final side = MethodChannel(name);
      messenger.setMockMethodCallHandler(side, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(side, null));
    }
  }

  Future<Object?> fromNative(String method, Object? arguments) {
    final replied = Completer<Object?>();
    messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      (data) => replied.complete(
        data == null ? null : channel.codec.decodeEnvelope(data),
      ),
    );
    return replied.future;
  }

  Future<String?> pendingToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(fcmPendingTokenKey);
  }

  Map<String, Object?> push(String eventId) => {
    'id': 'job-$eventId',
    'data': {'event_id': eventId, 'room_id': '!room:example.org'},
    'appInFront': false,
  };

  group('the ring hold', () {
    test('keeps the push client, so a Decline during the ring opens no '
        'second one', () async {
      installRingChannels();
      var builds = 0;
      final declined = Completer<void>();
      Client? declinedWith;
      final holdDone = Completer<void>();
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async {
          builds++;
          return _RingingClient();
        },
        hold: (runner) async {
          await declined.future;
          await runner.withClient((client) async => declinedWith = client);
          holdDone.complete();
        },
      );

      await runner.deliver(
        const PushNotification(
          eventId: r'$invite',
          roomId: '!room:example.org',
        ),
      );
      expect(runner.lastPushOutcome, IncomingPushOutcome.callRinging);
      expect(declined.isCompleted, isFalse);

      declined.complete();
      await holdDone.future;

      expect(builds, 1);
      expect(declinedWith, isNotNull);
    });

    test('is not started for a push that is not a ring', () async {
      var holds = 0;
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async => _RecordingClient(),
        hold: (_) async => holds++,
      );

      await runner.deliver(
        const PushNotification(eventId: r'$text', roomId: '!room:example.org'),
      );
      await pumpEventQueue();

      expect(runner.lastPushOutcome, IncomingPushOutcome.ignored);
      expect(holds, 0);
    });

    test('a throwing hold is swallowed rather than left unhandled', () async {
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async => _RecordingClient(),
        hold: (_) async => throw StateError('port already claimed'),
      );

      await expectLater(runner.onRinging!(), completes);
    });
  });

  group('the background runner', () {
    test('is one per isolate, not one per message', () {
      expect(identical(fcmBackgroundRunner(), fcmBackgroundRunner()), isTrue);
    });

    test('serializes a burst so two clients never overlap', () async {
      var open = 0;
      var maxOpen = 0;
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async {
          open++;
          maxOpen = open > maxOpen ? open : maxOpen;
          return _RecordingClient(onDispose: () => open--);
        },
        hold: (_) async {},
      );

      await Future.wait([
        for (var i = 0; i < 5; i++)
          runner.deliver(
            PushNotification(eventId: '\$burst$i', roomId: '!room:x'),
          ),
      ]);

      expect(maxOpen, 1);
    });
  });

  group('runFcmHeadless', () {
    test('serves pushes before it asks the router to take it', () async {
      final client = _RecordingClient();
      readyAnswer = () async {
        await fromNative('push', push(r'$early'));
        return true;
      };

      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () async {},
        prepare: () async => true,
      );

      expect(client.fetched, [r'$early']);
    });

    test('sets up only once the router has taken it', () async {
      var prepares = 0;
      int? preparesWhenAsked;
      readyAnswer = () async {
        preparesWhenAsked = prepares;
        return true;
      };

      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = _RecordingClient(),
        initCrashReporting: () async {},
        prepare: () async {
          prepares++;
          return true;
        },
      );
      await pumpEventQueue();

      expect(preparesWhenAsked, 0);
      expect(prepares, 1);
    });

    test('an engine the router passed over builds no client', () async {
      readyAnswer = () async => false;
      var prepares = 0;
      var builds = 0;
      final runner = HeadlessPushRunner()
        ..clientBuilder = () async {
          builds++;
          return _RecordingClient();
        };

      await runFcmHeadless(
        runner: runner,
        initCrashReporting: () async {},
        prepare: () async {
          prepares++;
          return prepareHeadlessPush(initializeNotifications: () async {});
        },
      );
      await pumpEventQueue();

      expect(calls, ['ready']);
      expect(prepares, 0);
      expect(builds, 0);
      expect(await fromNative('quiescent', null), isTrue);
    });

    test('a push that arrives before the router answers starts the setup '
        'itself', () async {
      final answered = Completer<bool>();
      readyAnswer = () => answered.future;
      final client = _RecordingClient();
      var prepares = 0;

      final started = runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () async {},
        prepare: () async {
          prepares++;
          return true;
        },
      );
      await pumpEventQueue();
      await fromNative('push', push(r'$one'));

      expect(client.fetched, [r'$one']);
      expect(prepares, 1);

      answered.complete(true);
      await started;
      await pumpEventQueue();
      expect(prepares, 1);
    });

    test('claims pushes before its setup finishes and handles them once '
        'it does', () async {
      final client = _RecordingClient();
      final setup = Completer<bool>();
      final runner = HeadlessPushRunner()..liveClient = client;

      await runFcmHeadless(
        runner: runner,
        initCrashReporting: () async {},
        prepare: () => setup.future,
      );
      expect(calls, ['ready']);

      var replied = false;
      final reply = fromNative('push', push(r'$one')).then((_) {
        replied = true;
      });
      await pumpEventQueue();
      expect(replied, isFalse);
      expect(client.fetched, isEmpty);

      setup.complete(true);
      await reply;
      expect(client.fetched, [r'$one']);
    });

    test('a failed setup answers its jobs unhandled, and the next job '
        'tries the setup again', () async {
      final client = _RecordingClient();
      final firstSetup = Completer<bool>();
      var prepares = 0;

      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () async {},
        prepare: () {
          prepares++;
          return prepares == 1 ? firstSetup.future : Future.value(true);
        },
      );
      final first = fromNative('push', push(r'$one'));
      await pumpEventQueue();
      firstSetup.complete(false);
      await first;
      expect(client.fetched, isEmpty);

      await fromNative('push', push(r'$two'));

      expect(prepares, 2);
      expect(client.fetched, [r'$two']);
    });

    test('a setup that throws is tried again too', () async {
      final client = _RecordingClient();
      var prepares = 0;
      readyAnswer = () async => false;

      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () async {},
        prepare: () async {
          prepares++;
          if (prepares == 1) throw StateError('no notifications');
          return true;
        },
      );
      await fromNative('push', push(r'$one'));
      await fromNative('push', push(r'$two'));

      expect(prepares, 2);
      expect(client.fetched, [r'$two']);
    });

    test('starts crash reporting only once the first job is done, and '
        'never holds up an answer for it', () async {
      var starts = 0;
      final client = _RecordingClient();
      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () {
          starts++;
          return Completer<void>().future;
        },
        prepare: () async => true,
      );
      expect(calls, ['ready']);
      expect(starts, 0);

      await fromNative('push', push(r'$one')).timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('crash reporting held up the answer'),
      );
      expect(starts, 1);

      await fromNative('push', push(r'$two'));
      expect(starts, 1);
      expect(client.fetched, [r'$one', r'$two']);
    });

    test(
      'an engine the router passed over never starts crash reporting',
      () async {
        readyAnswer = () async => false;
        var starts = 0;

        await runFcmHeadless(
          runner: HeadlessPushRunner()..liveClient = _RecordingClient(),
          initCrashReporting: () async => starts++,
          prepare: () async => true,
        );
        await pumpEventQueue();

        expect(starts, 0);
      },
    );

    test('a failing crash-reporting start does not break it', () async {
      final client = _RecordingClient();
      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () async => throw StateError('no DSN'),
        prepare: () async => true,
      );

      await fromNative('push', push(r'$one'));
      await fromNative('push', push(r'$two'));

      expect(client.fetched, [r'$one', r'$two']);
    });

    test('a badge-only push opens no client', () async {
      var builds = 0;
      await runFcmHeadless(
        runner: HeadlessPushRunner()
          ..clientBuilder = () async {
            builds++;
            return _RecordingClient();
          },
        initCrashReporting: () async {},
        prepare: () async => true,
      );

      await fromNative('push', {
        'id': 'job-badge',
        'data': {'unread': '0'},
        'appInFront': false,
      });
      await pumpEventQueue();

      expect(builds, 0);
    });

    test('a push for an event starts opening its client while the setup '
        'still runs', () async {
      final setup = Completer<bool>();
      var builds = 0;
      await runFcmHeadless(
        runner: HeadlessPushRunner()
          ..clientBuilder = () async {
            builds++;
            return _RecordingClient();
          },
        initCrashReporting: () async {},
        prepare: () => setup.future,
      );

      final job = fromNative('push', push(r'$one'));
      await pumpEventQueue();
      expect(builds, 1);

      setup.complete(true);
      await job;
      expect(builds, 1);
    });

    test('gives its idle client up when the app asks for it', () async {
      final requests = StreamController<void>.broadcast();
      addTearDown(requests.close);
      final built = <_RecordingClient>[];
      await runFcmHeadless(
        runner: HeadlessPushRunner()
          ..clientBuilder = () async {
            final client = _RecordingClient();
            built.add(client);
            return client;
          },
        initCrashReporting: () async {},
        prepare: () async => true,
        yieldRequests: requests.stream,
      );
      await fromNative('push', push(r'$one'));
      expect(built.single.disposeCalls, 0);

      requests.add(null);
      await pumpEventQueue();

      expect(built.single.disposeCalls, 1);
    });

    test(
      'settles an idle client away when asked whether it is quiet',
      () async {
        final built = <_RecordingClient>[];
        await runFcmHeadless(
          runner: HeadlessPushRunner()
            ..clientBuilder = () async {
              final client = _RecordingClient();
              built.add(client);
              return client;
            },
          initCrashReporting: () async {},
          prepare: () =>
              prepareHeadlessPush(initializeNotifications: () async {}),
        );
        await fromNative('push', push(r'$one'));
        expect(built.single.disposeCalls, 0);

        expect(await fromNative('quiescent', null), isTrue);
        expect(built.single.disposeCalls, 1);
      },
    );

    test('is not quiet while a job waits for its setup', () async {
      final setup = Completer<bool>();
      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = _RecordingClient(),
        initCrashReporting: () async {},
        prepare: () => setup.future,
      );

      final job = fromNative('push', push(r'$one'));
      await pumpEventQueue();
      expect(await fromNative('quiescent', null), isFalse);

      setup.complete(true);
      await job;
      expect(await fromNative('quiescent', null), isTrue);
    });

    test(
      'is quiet only once nothing is running, not even a ring hold',
      () async {
        installRingChannels();
        final hold = Completer<void>();
        final runner = buildFcmBackgroundRunner(
          clientBuilder: () async => _RingingClient(),
          hold: (_) => hold.future,
        );
        await runFcmHeadless(
          runner: runner,
          initCrashReporting: () async {},
          prepare: () async => true,
        );

        expect(await fromNative('quiescent', null), isTrue);
        await fromNative('push', push(r'$invite'));
        expect(runner.lastPushOutcome, IncomingPushOutcome.callRinging);
        expect(await fromNative('quiescent', null), isFalse);

        hold.complete();
        await pumpEventQueue();
        expect(await fromNative('quiescent', null), isTrue);
      },
    );

    test('hands a new token to the pusher refresh', () async {
      final tokens = <String>[];
      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = _RecordingClient(),
        initCrashReporting: () async {},
        prepare: () async => true,
        refreshToken: (_, token) async => tokens.add(token),
      );

      await fromNative('token', {'id': 'job', 'token': 'fresh'});

      expect(tokens, ['fresh']);
    });
  });

  group('refreshFcmPusherHeadless', () {
    late _RecordingClient client;
    late HeadlessPushRunner runner;

    setUp(() {
      client = _RecordingClient();
      runner = HeadlessPushRunner()..liveClient = client;
    });

    test('moves a registered device to the new token', () async {
      SharedPreferences.setMockInitialValues({'push.fcm.token': 'old'});

      await refreshFcmPusherHeadless(
        runner,
        'fresh',
        notificationsAllowed: () async => true,
      );

      expect(client.posted.single.pushkey, 'fresh');
      expect(client.posted.single.appId, fcmAppId);
      expect(client.deleted.single.pushkey, 'old');
      expect(
        readFcmRegistration(await SharedPreferences.getInstance()),
        'fresh',
      );
    });

    test('leaves a device that never registered alone', () async {
      await refreshFcmPusherHeadless(
        runner,
        'fresh',
        notificationsAllowed: () async => true,
      );

      expect(client.posted, isEmpty);
      expect(client.deleted, isEmpty);
    });

    test('does nothing for the token it already has', () async {
      SharedPreferences.setMockInitialValues({'push.fcm.token': 'same'});

      await refreshFcmPusherHeadless(
        runner,
        'same',
        notificationsAllowed: () async => true,
      );

      expect(client.posted, isEmpty);
    });

    test('does nothing while notifications are off', () async {
      SharedPreferences.setMockInitialValues({'push.fcm.token': 'old'});

      await refreshFcmPusherHeadless(
        runner,
        'fresh',
        notificationsAllowed: () async => false,
      );

      expect(client.posted, isEmpty);
      expect(readFcmRegistration(await SharedPreferences.getInstance()), 'old');
      expect(await pendingToken(), isNull);
    });

    test(
      'a token the homeserver did not take waits for the next client',
      () async {
        SharedPreferences.setMockInitialValues({'push.fcm.token': 'old'});
        runner = HeadlessPushRunner()
          ..liveClient = _RecordingClient(postFails: true);

        await refreshFcmPusherHeadless(
          runner,
          'fresh',
          notificationsAllowed: () async => true,
        );

        expect(await pendingToken(), 'fresh');
        expect(
          readFcmRegistration(await SharedPreferences.getInstance()),
          'old',
        );
      },
    );

    test('a token no client was free for waits for the next client', () async {
      SharedPreferences.setMockInitialValues({'push.fcm.token': 'old'});
      runner = HeadlessPushRunner()
        ..clientBuilder = (() async => throw const ClientLeaseDenied());

      await refreshFcmPusherHeadless(
        runner,
        'fresh',
        notificationsAllowed: () async => true,
      );

      expect(await pendingToken(), 'fresh');
    });

    test('a token that moves clears the one that was waiting', () async {
      SharedPreferences.setMockInitialValues({
        'push.fcm.token': 'old',
        fcmPendingTokenKey: 'older-attempt',
      });

      await refreshFcmPusherHeadless(
        runner,
        'fresh',
        notificationsAllowed: () async => true,
      );

      expect(client.posted.single.pushkey, 'fresh');
      expect(await pendingToken(), isNull);
    });
  });

  group('a token that waited', () {
    Future<_RecordingClient> openClient({bool postFails = false}) async {
      final client = _RecordingClient(postFails: postFails);
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async => client,
        hold: (_) async {},
      );
      await runner.deliver(
        const PushNotification(eventId: r'$text', roomId: '!room:example.org'),
      );
      await pumpEventQueue();
      return client;
    }

    test('is moved by the next client this engine opens', () async {
      SharedPreferences.setMockInitialValues({
        'push.fcm.token': 'old',
        fcmPendingTokenKey: 'fresh',
      });

      final client = await openClient();

      expect(client.posted.single.pushkey, 'fresh');
      expect(client.deleted.single.pushkey, 'old');
      expect(
        readFcmRegistration(await SharedPreferences.getInstance()),
        'fresh',
      );
      expect(await pendingToken(), isNull);
    });

    test('stays waiting when the homeserver still does not take it', () async {
      SharedPreferences.setMockInitialValues({
        'push.fcm.token': 'old',
        fcmPendingTokenKey: 'fresh',
      });

      await openClient(postFails: true);

      expect(await pendingToken(), 'fresh');
      expect(readFcmRegistration(await SharedPreferences.getInstance()), 'old');
    });

    test('is forgotten once it is already the registered one', () async {
      SharedPreferences.setMockInitialValues({
        'push.fcm.token': 'fresh',
        fcmPendingTokenKey: 'fresh',
      });

      final client = await openClient();

      expect(client.posted, isEmpty);
      expect(await pendingToken(), isNull);
    });

    test('is forgotten for a device no longer registered', () async {
      SharedPreferences.setMockInitialValues({fcmPendingTokenKey: 'fresh'});

      final client = await openClient();

      expect(client.posted, isEmpty);
      expect(await pendingToken(), isNull);
    });

    test('with none waiting, a new client posts nothing', () async {
      SharedPreferences.setMockInitialValues({'push.fcm.token': 'old'});

      final client = await openClient();

      expect(client.posted, isEmpty);
    });
  });
}
