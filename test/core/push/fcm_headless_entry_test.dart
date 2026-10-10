import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart'
    show fcmPendingTokenKey;
import 'package:zuno/core/push/fcm_headless_entry.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/fcm_registration_store.dart';
import 'package:zuno/core/push/headless_push_runner.dart';
import 'package:zuno/core/push/incoming_push_handler.dart';

import '../../helpers/headless_ring.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/push_test_client.dart';
import '../../helpers/pusher_recording_client.dart';

class _PusherPushClient extends PushTestClient with PusherRecording {
  _PusherPushClient() {
    homeserver = Uri.parse('https://matrix.example.org');
  }
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

  Future<Object?> fromNative(String method, Object? arguments) =>
      callFromNative(channel, method, arguments);

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
      installHeadlessRingChannels();
      final built = <PushTestClient>[];
      final declined = Completer<void>();
      Client? declinedWith;
      final holdDone = Completer<void>();
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async {
          final client = ringingPushClient();
          built.add(client);
          return client;
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

      expect(built, hasLength(1));
      expect(declinedWith, same(built.single));
    });

    test('a throwing hold is swallowed rather than left unhandled', () async {
      final runner = buildFcmBackgroundRunner(
        clientBuilder: () async => _PusherPushClient(),
        hold: (_) async => throw StateError('port already claimed'),
      );

      await expectLater(runner.onRinging!(), completes);
    });
  });

  group('the background runner', () {
    test('is one per isolate, not one per message', () {
      expect(identical(fcmBackgroundRunner(), fcmBackgroundRunner()), isTrue);
    });
  });

  group('runFcmHeadless', () {
    test('serves pushes before it asks the router to take it', () async {
      final client = _PusherPushClient();
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
        runner: HeadlessPushRunner()..liveClient = _PusherPushClient(),
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
          return _PusherPushClient();
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
      final client = _PusherPushClient();
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
      final client = _PusherPushClient();
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
      final client = _PusherPushClient();
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
      final client = _PusherPushClient();
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

    test('starts crash reporting with its setup, before the first push is '
        'handled, and never holds up an answer for it', () async {
      final answered = Completer<bool>();
      readyAnswer = () => answered.future;
      var starts = 0;
      int? startsWhenPrepared;
      final client = _PusherPushClient();
      final started = runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = client,
        initCrashReporting: () {
          starts++;
          return Completer<void>().future;
        },
        prepare: () async {
          startsWhenPrepared = starts;
          return true;
        },
      );
      await pumpEventQueue();
      expect(starts, 0);

      await fromNative('push', push(r'$one')).timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('crash reporting held up the answer'),
      );
      expect(startsWhenPrepared, 1);
      expect(client.fetched, [r'$one']);

      answered.complete(true);
      await started;
      await fromNative('push', push(r'$two'));
      expect(starts, 1);
      expect(client.fetched, [r'$one', r'$two']);
    });

    test('starts crash reporting once the router takes it, with no push '
        'yet', () async {
      var starts = 0;
      await runFcmHeadless(
        runner: HeadlessPushRunner()..liveClient = _PusherPushClient(),
        initCrashReporting: () async => starts++,
        prepare: () async => true,
      );

      expect(starts, 1);
    });

    test(
      'an engine the router passed over never starts crash reporting',
      () async {
        readyAnswer = () async => false;
        var starts = 0;

        await runFcmHeadless(
          runner: HeadlessPushRunner()..liveClient = _PusherPushClient(),
          initCrashReporting: () async => starts++,
          prepare: () async => true,
        );
        await pumpEventQueue();

        expect(starts, 0);
      },
    );

    test('a failing crash-reporting start does not break it', () async {
      final client = _PusherPushClient();
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
            return _PusherPushClient();
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
            return _PusherPushClient();
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
      final built = <PushTestClient>[];
      await runFcmHeadless(
        runner: HeadlessPushRunner()
          ..clientBuilder = () async {
            final client = _PusherPushClient();
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
        final built = <PushTestClient>[];
        await runFcmHeadless(
          runner: HeadlessPushRunner()
            ..clientBuilder = () async {
              final client = _PusherPushClient();
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
        runner: HeadlessPushRunner()..liveClient = _PusherPushClient(),
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
        installHeadlessRingChannels();
        final hold = Completer<void>();
        final runner = buildFcmBackgroundRunner(
          clientBuilder: () async => ringingPushClient(),
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
        runner: HeadlessPushRunner()..liveClient = _PusherPushClient(),
        initCrashReporting: () async {},
        prepare: () async => true,
        refreshToken: (_, token) async => tokens.add(token),
      );

      await fromNative('token', {'id': 'job', 'token': 'fresh'});

      expect(tokens, ['fresh']);
    });
  });

  group('refreshFcmPusherHeadless', () {
    late _PusherPushClient client;
    late HeadlessPushRunner runner;

    setUp(() {
      client = _PusherPushClient();
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
          ..liveClient = (_PusherPushClient()
            ..postError = StateError('homeserver unreachable'));

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
    Future<_PusherPushClient> openClient({bool postFails = false}) async {
      final client = _PusherPushClient();
      if (postFails) client.postError = StateError('homeserver unreachable');
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
