import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/fcm_registration_store.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/pusher_recording_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FcmDeliveryProvider provider;
  late PusherRecordingClient client;
  var availability = FcmAvailability.available;
  var availabilityChecks = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    availability = FcmAvailability.available;
    availabilityChecks = 0;
    client = PusherRecordingClient();
    provider = FcmDeliveryProvider()
      ..availabilityReader = (() async {
        availabilityChecks++;
        return availability;
      })
      ..tokenReader = (() async => 'token-abc')
      ..tokenDeleter = (() async {});
  });

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

  test('stops at playServicesUnavailable without touching the homeserver or '
      'scheduling a retry', () async {
    availability = FcmAvailability.unavailable;

    await provider.start(client);

    expect(provider.status.value, FcmStatus.playServicesUnavailable);
    expect(client.posted, isEmpty);
    expect(provider.retryScheduled, isFalse);
  });

  test('distinguishes an update from an absence', () async {
    availability = FcmAvailability.updateRequired;

    await provider.start(client);

    expect(provider.status.value, FcmStatus.playServicesUpdateRequired);
    expect(client.posted, isEmpty);
  });

  test('tells a turned-off Google Play services apart', () async {
    availability = FcmAvailability.disabled;

    await provider.start(client);

    expect(provider.status.value, FcmStatus.playServicesDisabled);
    expect(client.posted, isEmpty);
    expect(provider.retryScheduled, isFalse);
  });

  test('a build without Google services stops at notConfigured and never '
      'asks for a token', () async {
    availability = FcmAvailability.notConfigured;
    var tokenReads = 0;
    provider.tokenReader = () async {
      tokenReads++;
      return 'token-abc';
    };

    await provider.start(client);

    expect(provider.status.value, FcmStatus.notConfigured);
    expect(tokenReads, 0);
    expect(provider.retryScheduled, isFalse);
  });

  group('a token request that fails', () {
    setUp(() => addTearDown(() => provider.stop(client)));

    test('because Google Play services is missing is not retried', () async {
      provider.tokenReader = () async =>
          throw const FcmTokenException(FcmTokenFailure.noPlayServices);

      await provider.start(client);

      expect(provider.status.value, FcmStatus.playServicesUnavailable);
      expect(provider.retryScheduled, isFalse);
      expect(client.posted, isEmpty);
    });

    test('because the build has no Google services is not retried', () async {
      provider.tokenReader = () async =>
          throw const FcmTokenException(FcmTokenFailure.notConfigured);

      await provider.start(client);

      expect(provider.status.value, FcmStatus.notConfigured);
      expect(provider.retryScheduled, isFalse);
    });

    for (final failure in [
      FcmTokenFailure.unavailable,
      FcmTokenFailure.failed,
    ]) {
      test('with ${failure.name} is retried later', () async {
        provider
          ..retryDelay = ((_) => const Duration(days: 1))
          ..tokenReader = () async => throw FcmTokenException(failure);

        await provider.start(client);

        expect(provider.status.value, FcmStatus.tokenFailed);
        expect(provider.retryScheduled, isTrue);
      });
    }

    group('is reported', () {
      setUp(
        () => provider
          ..retryDelay = ((_) => const Duration(days: 1))
          ..notificationsAllowed = (() async => true),
      );

      test('never while Google cannot be reached, which a retry '
          'covers', () async {
        provider.tokenReader = () async =>
            throw const FcmTokenException(FcmTokenFailure.unavailable);

        expect(await reportsDuring(() => provider.start(client)), isEmpty);
      });

      test('when Firebase fails it any other way', () async {
        provider.tokenReader = () async =>
            throw const FcmTokenException(FcmTokenFailure.failed);

        expect(await reportsDuring(() => provider.start(client)), [
          'fcm token request',
        ]);
      });

      test('on a restored registration, never while Google cannot be '
          'reached', () async {
        SharedPreferences.setMockInitialValues({'push.fcm.token': 'token-abc'});
        client.pushersOnServer = [
          serverPusherJson(appId: fcmAppId, pushkey: 'token-abc'),
        ];
        provider.tokenReader = () async =>
            throw const FcmTokenException(FcmTokenFailure.unavailable);

        expect(await reportsDuring(() => provider.start(client)), isEmpty);
      });

      test('on a restored registration, when Firebase fails it any other '
          'way', () async {
        SharedPreferences.setMockInitialValues({'push.fcm.token': 'token-abc'});
        client.pushersOnServer = [
          serverPusherJson(appId: fcmAppId, pushkey: 'token-abc'),
        ];
        provider.tokenReader = () async =>
            throw const FcmTokenException(FcmTokenFailure.failed);

        expect(await reportsDuring(() => provider.start(client)), [
          'fcm token check',
        ]);
      });
    });
  });

  group('fixPlayServices', () {
    test('registers once Google reports the device fixed', () async {
      availability = FcmAvailability.updateRequired;
      await provider.start(client);
      expect(provider.status.value, FcmStatus.playServicesUpdateRequired);

      provider.playServicesFixer = () async {
        availability = FcmAvailability.available;
        return availability;
      };
      await provider.fixPlayServices(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(client.posted, hasLength(1));
    });

    test('keeps the status when the fix did not help', () async {
      availability = FcmAvailability.updateRequired;
      await provider.start(client);

      provider.playServicesFixer = () async => availability;
      await provider.fixPlayServices(client);

      expect(provider.status.value, FcmStatus.playServicesUpdateRequired);
      expect(client.posted, isEmpty);
    });
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
      client.pushersOnServer = [
        serverPusherJson(appId: fcmAppId, pushkey: 'token-abc'),
      ];
      now = now.add(registrationRecheckInterval);

      await provider.recheckRegistration(client);

      expect(client.posted, hasLength(1));
    });

    for (final blocked in [
      FcmAvailability.updateRequired,
      FcmAvailability.disabled,
      FcmAvailability.unavailable,
    ]) {
      test('registers on resume once a ${blocked.name} device is '
          'fixed', () async {
        availability = blocked;
        await provider.start(client);
        expect(client.posted, isEmpty);

        availability = FcmAvailability.available;
        await provider.recheckRegistration(client);

        expect(provider.status.value, FcmStatus.ready);
        expect(client.posted, hasLength(1));
      });
    }

    test('stays put on resume while the device still cannot use Google '
        'services', () async {
      availability = FcmAvailability.updateRequired;
      await provider.start(client);
      final checks = availabilityChecks;

      await provider.recheckRegistration(client);

      expect(availabilityChecks, checks + 1);
      expect(provider.status.value, FcmStatus.playServicesUpdateRequired);
      expect(client.posted, isEmpty);
    });

    test('never re-checks a build without Google services', () async {
      availability = FcmAvailability.notConfigured;
      await provider.start(client);
      final checks = availabilityChecks;

      await provider.recheckRegistration(client);

      expect(availabilityChecks, checks);
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

  test('a refreshed token re-registers under the new pushkey and removes the '
      'pusher it replaces', () async {
    final refreshes = StreamController<String>.broadcast();
    provider.tokenRefreshStream = () => refreshes.stream;
    addTearDown(refreshes.close);
    await provider.start(client);

    refreshes.add('token-def');
    await pumpEventQueue();

    expect(client.posted, hasLength(2));
    expect(client.posted.last.pushkey, 'token-def');
    expect(provider.token, 'token-def');
    expect(client.deleted.single.pushkey, 'token-abc');
    expect(
      readFcmRegistration(await SharedPreferences.getInstance()),
      'token-def',
    );
  });

  test('a refresh to the same token changes nothing', () async {
    final refreshes = StreamController<String>.broadcast();
    provider.tokenRefreshStream = () => refreshes.stream;
    addTearDown(refreshes.close);
    await provider.start(client);

    refreshes.add('token-abc');
    await pumpEventQueue();

    expect(client.posted, hasLength(1));
    expect(client.deleted, isEmpty);
  });

  test('stop after the session ended asks the homeserver nothing and shows '
      'no error, since the pusher went with the session', () async {
    await provider.start(client);
    client.signedIn = false;

    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(provider.lastPusherError, isNull);
    expect(provider.status.value, FcmStatus.idle);
  });

  test('stop shows a pusher delete the homeserver refuses', () async {
    await provider.start(client);
    client.deleteError = MatrixException.fromJson({'errcode': 'M_FORBIDDEN'});

    await provider.stop(client);

    expect(provider.lastPusherError, contains('M_FORBIDDEN'));
    expect(provider.status.value, FcmStatus.idle);
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

  group('with notifications off', () {
    setUp(() => provider.notificationsAllowed = () async => false);

    test('start registers nothing', () async {
      await provider.start(client);

      expect(client.posted, isEmpty);
      expect(provider.status.value, FcmStatus.idle);
    });

    test('registerNow registers nothing', () async {
      await provider.registerNow(client);

      expect(client.posted, isEmpty);
      expect(provider.status.value, FcmStatus.idle);
    });

    test(
      'start does not restore a registration from an earlier process',
      () async {
        SharedPreferences.setMockInitialValues({'push.fcm.token': 'token-abc'});

        await provider.start(client);

        expect(provider.status.value, FcmStatus.idle);
        expect(provider.token, isNull);
      },
    );
  });

  test(
    'a refreshed token is not registered once notifications are off',
    () async {
      final refreshes = StreamController<String>.broadcast();
      provider.tokenRefreshStream = () => refreshes.stream;
      addTearDown(refreshes.close);
      await provider.start(client);

      provider.notificationsAllowed = () async => false;
      refreshes.add('token-def');
      await pumpEventQueue();

      expect(client.posted, hasLength(1));
      expect(provider.token, 'token-abc');
    },
  );

  test('stop tears down a registration persisted by an earlier process, '
      'even though start() never ran in this one', () async {
    SharedPreferences.setMockInitialValues({'push.fcm.token': 'token-abc'});
    var tokenDeleted = false;
    provider.tokenDeleter = () async => tokenDeleted = true;

    await provider.stop(client);

    expect(client.deleted.single.pushkey, 'token-abc');
    expect(tokenDeleted, isTrue);
    expect(readFcmRegistration(await SharedPreferences.getInstance()), isNull);
    expect(provider.status.value, FcmStatus.idle);
  });

  test('stop is a no-op when nothing was ever registered', () async {
    await provider.stop(client);

    expect(client.deleted, isEmpty);
    expect(provider.status.value, FcmStatus.idle);
  });

  group('a push target the user removes', () {
    test('is taken down and marked removed', () async {
      await provider.start(client);

      await provider.remove(client);

      expect(provider.removed.value, isTrue);
      expect(provider.status.value, FcmStatus.idle);
      expect(provider.registered, isFalse);
      expect(client.deleted.single.pushkey, 'token-abc');
      expect(
        readFcmRegistration(await SharedPreferences.getInstance()),
        isNull,
      );
    });

    test('is no longer marked once registering again', () async {
      await provider.start(client);
      await provider.remove(client);

      await provider.registerNow(client);

      expect(provider.removed.value, isFalse);
      expect(provider.status.value, FcmStatus.ready);
      expect(client.posted, hasLength(2));
    });

    test('is registered again by the next start', () async {
      await provider.start(client);
      await provider.remove(client);

      await provider.start(client);

      expect(provider.removed.value, isFalse);
      expect(provider.status.value, FcmStatus.ready);
      expect(client.posted, hasLength(2));
    });

    test('a registration that fails again reports that failure '
        'instead', () async {
      provider.retryDelay = (_) => const Duration(days: 1);
      addTearDown(() => provider.stop(client));
      await provider.start(client);
      await provider.remove(client);
      client.postError = Exception('server said no');

      await provider.registerNow(client);

      expect(provider.removed.value, isFalse);
      expect(provider.status.value, FcmStatus.pusherFailed);
    });

    test('is no longer marked once a refreshed token registers', () async {
      final refreshes = StreamController<String>.broadcast();
      provider.tokenRefreshStream = () => refreshes.stream;
      addTearDown(refreshes.close);
      await provider.start(client);
      provider.removed.value = true;

      refreshes.add('token-def');
      await pumpEventQueue();

      expect(provider.removed.value, isFalse);
    });

    test('is no longer marked once stopped', () async {
      await provider.start(client);
      await provider.remove(client);

      await provider.stop(client);

      expect(provider.removed.value, isFalse);
    });

    test('is never marked by stop alone', () async {
      await provider.start(client);

      await provider.stop(client);
      expect(provider.removed.value, isFalse);

      await provider.stop(client);
      expect(provider.removed.value, isFalse);
    });
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
      client.pushersOnServer = [
        serverPusherJson(appId: fcmAppId, pushkey: 'somebody-elses-token'),
      ];

      await provider.start(client);

      expect(client.posted, hasLength(1));
      expect(client.posted.single.pushkey, 'token-abc');
      expect(provider.status.value, FcmStatus.ready);
    });

    test('leaves a confirmed registration alone when the homeserver still '
        'has it', () async {
      client.pushersOnServer = [
        serverPusherJson(appId: fcmAppId, pushkey: 'token-abc'),
      ];

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

    for (final (label, lost, status) in [
      (
        'Google Play services is gone',
        FcmAvailability.unavailable,
        FcmStatus.playServicesUnavailable,
      ),
      (
        'Google Play services needs an update',
        FcmAvailability.updateRequired,
        FcmStatus.playServicesUpdateRequired,
      ),
      (
        'Google Play services is turned off',
        FcmAvailability.disabled,
        FcmStatus.playServicesDisabled,
      ),
    ]) {
      test('is not reported active when $label', () async {
        availability = lost;
        var tokenReads = 0;
        provider.tokenReader = () async {
          tokenReads++;
          return 'token-abc';
        };

        await provider.start(client);

        expect(provider.status.value, status);
        expect(tokenReads, 0);
        expect(client.posted, isEmpty);
        expect(
          readFcmRegistration(await SharedPreferences.getInstance()),
          'token-abc',
        );
      });
    }

    test('checks the device once per start', () async {
      await provider.start(client);

      expect(availabilityChecks, 1);
    });

    test('re-registers a token that rotated while the app was off, and '
        'removes the pusher it replaces', () async {
      provider.tokenReader = () async => 'token-rotated';

      await provider.start(client);

      expect(client.posted, hasLength(1));
      expect(client.posted.single.pushkey, 'token-rotated');
      expect(client.deleted.single.pushkey, 'token-abc');
      expect(provider.status.value, FcmStatus.ready);
    });

    test('is kept, with the device\'s state shown, while Google Play services '
        'is turned off', () async {
      availability = FcmAvailability.disabled;

      await provider.start(client);

      expect(provider.status.value, FcmStatus.playServicesDisabled);
      expect(provider.registered, isTrue);
      expect(provider.token, 'token-abc');
      expect(client.deleted, isEmpty);
    });

    test('stays active when the device check itself fails, and asks again on '
        'the next resume', () async {
      availability = FcmAvailability.unknown;

      await provider.start(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(provider.registered, isTrue);

      availability = FcmAvailability.disabled;
      await provider.recheckRegistration(client);

      expect(provider.status.value, FcmStatus.playServicesDisabled);
      expect(provider.registered, isTrue);
      expect(client.deleted, isEmpty);
    });

    test('a device check that keeps failing changes nothing on '
        'resume', () async {
      availability = FcmAvailability.unknown;
      await provider.start(client);
      final checks = availabilityChecks;

      await provider.recheckRegistration(client);

      expect(availabilityChecks, checks + 1);
      expect(provider.status.value, FcmStatus.ready);
    });

    test('a device check that answers on resume is not asked again', () async {
      availability = FcmAvailability.unknown;
      await provider.start(client);
      availability = FcmAvailability.available;
      await provider.recheckRegistration(client);
      final checks = availabilityChecks;

      await provider.recheckRegistration(client);

      expect(availabilityChecks, checks);
    });
  });

  group('following the token FCM has now', () {
    setUp(
      () => SharedPreferences.setMockInitialValues({
        'push.fcm.token': 'token-abc',
      }),
    );

    Future<SharedPreferences> prefs() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs;
    }

    test('a resume moves the pusher to a token that changed since '
        'start', () async {
      await provider.start(client);
      provider.tokenReader = () async => 'token-new';

      await provider.recheckRegistration(client);

      expect(client.posted.single.pushkey, 'token-new');
      expect(client.deleted.single.pushkey, 'token-abc');
      expect(provider.token, 'token-new');
      expect(readFcmRegistration(await prefs()), 'token-new');
    });

    test('a token change found on resume is not posted once notifications are '
        'off', () async {
      await provider.start(client);
      provider
        ..tokenReader = (() async => 'token-new')
        ..notificationsAllowed = (() async => false);

      await provider.recheckRegistration(client);

      expect(client.posted, isEmpty);
      expect(provider.token, 'token-abc');
    });

    test('a resume with the same token posts nothing', () async {
      await provider.start(client);

      await provider.recheckRegistration(client);

      expect(client.posted, isEmpty);
    });

    test('a token the background engine could not post is posted on the '
        'next resume, then forgotten', () async {
      await provider.start(client);
      provider.tokenReader = () async => throw Exception('no network');
      await (await prefs()).setString(fcmPendingTokenKey, 'token-pending');

      await provider.recheckRegistration(client);

      expect(client.posted.single.pushkey, 'token-pending');
      expect(client.deleted.single.pushkey, 'token-abc');
      expect((await prefs()).getString(fcmPendingTokenKey), isNull);
      expect(readFcmRegistration(await prefs()), 'token-pending');
    });

    test('start posts a token the background engine could not post', () async {
      provider.tokenReader = () async => throw Exception('no network');
      await (await prefs()).setString(fcmPendingTokenKey, 'token-pending');

      await provider.start(client);

      expect(client.posted.single.pushkey, 'token-pending');
      expect(provider.status.value, FcmStatus.ready);
      expect((await prefs()).getString(fcmPendingTokenKey), isNull);
    });

    test('a pending token waits for a later try when its post fails', () async {
      provider.tokenReader = () async => throw Exception('no network');
      await (await prefs()).setString(fcmPendingTokenKey, 'token-pending');
      client.postError = Exception('offline');

      await provider.start(client);

      expect(provider.status.value, FcmStatus.pusherFailed);
      expect((await prefs()).getString(fcmPendingTokenKey), 'token-pending');
      expect(provider.registered, isTrue);
    });

    test('a pending token FCM has moved past is dropped, not posted', () async {
      await (await prefs()).setString(fcmPendingTokenKey, 'token-stale');

      await provider.start(client);

      expect(client.posted, isEmpty);
      expect((await prefs()).getString(fcmPendingTokenKey), isNull);
    });

    test('a pusher the background engine moved is adopted, so the next '
        'token change removes the right one', () async {
      await provider.start(client);
      await (await prefs()).setString('push.fcm.token', 'token-moved');
      provider.tokenReader = () async => 'token-moved';

      await provider.recheckRegistration(client);

      expect(client.posted, isEmpty);
      expect(provider.token, 'token-moved');
    });

    test('stop removes the pusher the background engine moved to as well as '
        'the one this app knew, and forgets a pending token', () async {
      await provider.start(client);
      await (await prefs()).setString('push.fcm.token', 'token-moved');
      await (await prefs()).setString(fcmPendingTokenKey, 'token-pending');

      await provider.stop(client);

      expect(
        client.deleted.map((p) => p.pushkey),
        unorderedEquals(['token-abc', 'token-moved']),
      );
      expect((await prefs()).getString(fcmPendingTokenKey), isNull);
      expect(provider.registered, isFalse);
    });
  });

  group('a device check that fails', () {
    setUp(() => availability = FcmAvailability.unknown);

    test('never stops a first registration: the token request '
        'decides', () async {
      await provider.start(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(client.posted.single.pushkey, 'token-abc');
    });

    test('while the device is blocked keeps the blocked state and asks for no '
        'token', () async {
      availability = FcmAvailability.disabled;
      var tokenReads = 0;
      provider.tokenReader = () async {
        tokenReads++;
        return 'token-abc';
      };
      await provider.start(client);

      availability = FcmAvailability.unknown;
      await provider.recheckRegistration(client);

      expect(provider.status.value, FcmStatus.playServicesDisabled);
      expect(tokenReads, 0);
    });

    test('after a fix registers, so the token request decides', () async {
      provider.playServicesFixer = () async => FcmAvailability.unknown;

      await provider.fixPlayServices(client);

      expect(provider.status.value, FcmStatus.ready);
      expect(client.posted, hasLength(1));
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
        ..availabilityReader = (() async => FcmAvailability.available)
        ..tokenReader = (() async => 'token-abc')
        ..tokenDeleter = (() async {});
      final freshClient = PusherRecordingClient();
      await relaunched.start(freshClient);
      expect(freshClient.posted, hasLength(1));
    },
  );

  test(
    'does not register without a homeserver to derive the gateway from',
    () async {
      final unset = PusherRecordingClient()..homeserver = null;

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
