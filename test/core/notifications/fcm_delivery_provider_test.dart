import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/fcm_registration_store.dart';

import '../../helpers/fake_matrix.dart';

class _RecordingClient extends Client {
  _RecordingClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  final posted = <Pusher>[];
  final deleted = <PusherId>[];
  Object? postError;

  void Function()? onDeletePusher;

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {
    if (postError != null) throw postError!;
    posted.add(pusher);
  }

  @override
  Future<void> deletePusher(PusherId pusherId) async {
    onDeletePusher?.call();
    deleted.add(pusherId);
  }

  List<Map<String, Object?>>? pushersOnServer;

  @override
  Future<Map<String, Object?>> request(
    RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    if (action != '/client/v3/pushers') {
      return super.request(type, action, data: data, query: query);
    }
    final pushers = pushersOnServer;
    if (pushers == null) throw Exception('offline');
    return {'pushers': pushers};
  }
}

Map<String, Object?> _serverPusher(String pushkey) => {
  'app_id': fcmAppId,
  'pushkey': pushkey,
  'app_display_name': 'Zuno Chat',
  'device_display_name': 'Phone',
  'kind': 'http',
  'lang': 'en',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/play_services');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late FcmDeliveryProvider provider;
  late _RecordingClient client;
  String playServices = 'AVAILABLE';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playServices = 'AVAILABLE';
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'checkPlayServices' ? playServices : null,
    );
    client = _RecordingClient();
    provider = FcmDeliveryProvider()
      ..tokenReader = (() async => 'token-abc')
      ..tokenDeleter = (() async {});
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('registers a pusher and reports ready', () async {
    await provider.start(client);

    expect(provider.status.value, FcmStatus.ready);
    expect(client.posted, hasLength(1));
    expect(client.posted.single.pushkey, 'token-abc');
    expect(client.posted.single.appId, 'im.zuno.chat.android');
    expect(
      client.posted.single.data.url,
      Uri.parse('https://matrix.example.org/_matrix/push/v1/notify'),
    );
  });

  test(
    'is idempotent across the repeated start() calls _AuthGate makes',
    () async {
      await provider.start(client);
      await provider.start(client);
      await provider.start(client);

      expect(client.posted, hasLength(1));
    },
  );

  test(
    'stops at playServicesUnavailable without touching the homeserver',
    () async {
      playServices = 'UNAVAILABLE';

      await provider.start(client);

      expect(provider.status.value, FcmStatus.playServicesUnavailable);
      expect(client.posted, isEmpty);
    },
  );

  test('distinguishes an update from an absence', () async {
    playServices = 'UPDATE_REQUIRED';

    await provider.start(client);

    expect(provider.status.value, FcmStatus.playServicesUpdateRequired);
    expect(client.posted, isEmpty);
  });

  test('reports tokenFailed when Firebase yields no token', () async {
    provider.tokenReader = () async => null;

    await provider.start(client);

    expect(provider.status.value, FcmStatus.tokenFailed);
    expect(client.posted, isEmpty);
  });

  test(
    'a failed registration is not re-attempted by a repeated start()',
    () async {
      client.postError = Exception('server said no');

      await provider.start(client);
      expect(provider.status.value, FcmStatus.pusherFailed);
      expect(provider.lastPusherError, contains('server said no'));

      await provider.start(client);
      expect(client.posted, isEmpty);
      expect(provider.status.value, FcmStatus.pusherFailed);
    },
  );

  group('retry after a transient failure', () {
    setUp(() {
      provider.retryDelay = (attempt) =>
          attempt < 3 ? Duration.zero : const Duration(days: 1);
      addTearDown(() => provider.stop(client));
    });

    test(
      'a rejected pusher is retried by itself once the delay passes',
      () async {
        client.postError = Exception('server said no');
        await provider.start(client);
        expect(provider.retryScheduled, isTrue);
        client.postError = null;

        await pumpEventQueue();

        expect(provider.status.value, FcmStatus.ready);
        expect(client.posted, hasLength(1));
        expect(provider.retryScheduled, isFalse);
      },
    );

    test('a missing token is retried too', () async {
      var reads = 0;
      provider.tokenReader = () async => ++reads == 1 ? null : 'token-abc';
      await provider.start(client);
      expect(provider.status.value, FcmStatus.tokenFailed);

      await pumpEventQueue();

      expect(provider.status.value, FcmStatus.ready);
    });

    test(
      'keeps backing off while the failure persists, without spinning',
      () async {
        client.postError = Exception('server said no');
        var attempts = 0;
        provider.retryDelay = (attempt) {
          attempts = attempt;
          return attempt < 3 ? Duration.zero : const Duration(days: 1);
        };

        await provider.start(client);
        await pumpEventQueue();

        expect(attempts, 3);
        expect(provider.status.value, FcmStatus.pusherFailed);
      },
    );

    test('no Play Services is not something to retry in a loop', () async {
      playServices = 'UNAVAILABLE';

      await provider.start(client);

      expect(provider.retryScheduled, isFalse);
    });

    test('stop cancels a pending retry', () async {
      client.postError = Exception('server said no');
      provider.retryDelay = (_) => const Duration(days: 1);
      await provider.start(client);
      expect(provider.retryScheduled, isTrue);

      await provider.stop(client);

      expect(provider.retryScheduled, isFalse);
    });

    test('retryIfFailed registers straight away', () async {
      client.postError = Exception('server said no');
      provider.retryDelay = (_) => const Duration(days: 1);
      await provider.start(client);
      client.postError = null;

      await provider.retryIfFailed(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(provider.retryScheduled, isFalse);
    });

    test('retryIfFailed is a no-op when nothing failed', () async {
      await provider.start(client);

      await provider.retryIfFailed(client);

      expect(client.posted, hasLength(1));
    });
  });

  test(
    'the default backoff doubles from a minute and caps at half an hour',
    () {
      expect(defaultRegistrationRetryDelay(0), const Duration(minutes: 1));
      expect(defaultRegistrationRetryDelay(1), const Duration(minutes: 2));
      expect(defaultRegistrationRetryDelay(4), const Duration(minutes: 16));
      expect(defaultRegistrationRetryDelay(9), const Duration(minutes: 30));
    },
  );

  group('recheckRegistration on resume', () {
    var now = DateTime(2031, 1, 1, 9);

    setUp(() {
      now = DateTime(2031, 1, 1, 9);
      provider.now = () => now;
    });

    test('re-posts a pusher the homeserver has since dropped', () async {
      await provider.start(client);
      client.pushersOnServer = [];
      now = now.add(registrationRecheckInterval);

      await provider.recheckRegistration(client);

      expect(client.posted, hasLength(2));
      expect(provider.status.value, FcmStatus.ready);
    });

    test('does not ask the homeserver again within the interval', () async {
      await provider.start(client);
      client.pushersOnServer = [];
      now = now.add(const Duration(minutes: 5));

      await provider.recheckRegistration(client);

      expect(client.posted, hasLength(1));
    });

    test('leaves a registration the homeserver still has alone', () async {
      await provider.start(client);
      client.pushersOnServer = [_serverPusher('token-abc')];
      now = now.add(registrationRecheckInterval);

      await provider.recheckRegistration(client);

      expect(client.posted, hasLength(1));
    });

    test('does nothing when not registered at all', () async {
      now = now.add(registrationRecheckInterval);

      await provider.recheckRegistration(client);

      expect(client.posted, isEmpty);
    });
  });

  test('registerNow retries after a failure', () async {
    client.postError = Exception('server said no');
    await provider.start(client);
    client.postError = null;

    await provider.registerNow(client);

    expect(provider.status.value, FcmStatus.ready);
    expect(client.posted, hasLength(1));
  });

  test('a refreshed token re-registers under the new pushkey', () async {
    final refreshes = StreamController<String>.broadcast();
    provider.tokenRefreshStream = () => refreshes.stream;
    addTearDown(refreshes.close);
    await provider.start(client);

    refreshes.add('token-def');
    await pumpEventQueue();

    expect(client.posted, hasLength(2));
    expect(client.posted.last.pushkey, 'token-def');
    expect(provider.token, 'token-def');
  });

  test('stop deletes the pusher before deleting the token', () async {
    final order = <String>[];
    client.onDeletePusher = () => order.add('pusher');
    provider.tokenDeleter = () async => order.add('token');
    await provider.start(client);

    await provider.stop(client);

    expect(client.deleted.single.pushkey, 'token-abc');
    expect(client.deleted.single.appId, 'im.zuno.chat.android');
    expect(order, ['pusher', 'token']);
    expect(provider.status.value, FcmStatus.idle);
  });

  test('stop is a no-op when nothing was ever registered', () async {
    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(provider.status.value, FcmStatus.idle);
  });

  group('a registration the homeserver already confirmed', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'push.fcm.token': 'token-abc',
      }),
    );

    test('is restored without asking the homeserver again', () async {
      await provider.start(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(provider.token, 'token-abc');
      expect(client.posted, isEmpty);
    });

    test('survives a homeserver that is unreachable at launch', () async {
      client.postError = Exception('SocketException: failed host lookup');

      await provider.start(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(provider.lastPusherError, isNull);
    });

    test('survives a token read that throws', () async {
      provider.tokenReader = () async => throw Exception('no network');

      await provider.start(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(provider.token, 'token-abc');
    });

    test('re-posts when the homeserver has dropped the pusher', () async {
      client.pushersOnServer = [_serverPusher('somebody-elses-token')];

      await provider.start(client);

      expect(client.posted, hasLength(1));
      expect(client.posted.single.pushkey, 'token-abc');
      expect(provider.status.value, FcmStatus.ready);
    });

    test('leaves a confirmed registration alone when the homeserver still '
        'has it', () async {
      client.pushersOnServer = [_serverPusher('token-abc')];

      await provider.start(client);

      expect(client.posted, isEmpty);
      expect(provider.status.value, FcmStatus.ready);
    });

    test('does not re-post when the pusher list cannot be read', () async {
      client.pushersOnServer = null;

      await provider.start(client);

      expect(client.posted, isEmpty);
      expect(provider.status.value, FcmStatus.ready);
    });

    test('re-registers a token that rotated while the app was off', () async {
      provider.tokenReader = () async => 'token-rotated';

      await provider.start(client);

      expect(client.posted, hasLength(1));
      expect(client.posted.single.pushkey, 'token-rotated');
      expect(provider.status.value, FcmStatus.ready);
    });
  });

  test(
    'remembers a registration only once the homeserver accepts it',
    () async {
      client.postError = Exception('server said no');
      await provider.start(client);
      expect(
        readFcmRegistration(await SharedPreferences.getInstance()),
        isNull,
      );

      client.postError = null;
      await provider.registerNow(client);

      expect(
        readFcmRegistration(await SharedPreferences.getInstance()),
        'token-abc',
      );
    },
  );

  test(
    'stop forgets the confirmation, so the next launch registers afresh',
    () async {
      await provider.start(client);
      await provider.stop(client);

      expect(
        readFcmRegistration(await SharedPreferences.getInstance()),
        isNull,
      );
      final relaunched = FcmDeliveryProvider()
        ..tokenReader = (() async => 'token-abc')
        ..tokenDeleter = (() async {});
      final freshClient = _RecordingClient();
      await relaunched.start(freshClient);
      expect(freshClient.posted, hasLength(1));
    },
  );

  test(
    'does not register without a homeserver to derive the gateway from',
    () async {
      final unset = _RecordingClient()..homeserver = null;

      await provider.start(unset);

      expect(unset.posted, isEmpty);
      expect(provider.status.value, FcmStatus.pusherFailed);
      expect(
        provider.lastPusherError,
        contains('No server to send notifications through yet.'),
      );
    },
  );
}
