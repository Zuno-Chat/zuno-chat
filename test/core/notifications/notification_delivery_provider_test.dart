import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/background_sync_delivery_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';
import 'package:zuno/core/push/voip/voip_channel.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

const _apnsToken =
    'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
const _apnsPushkey = 'obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/background_sync');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('background sync does not start while notifications are off', () async {
    final provider = BackgroundSyncDeliveryProvider()
      ..notificationsAllowed = () async => false;

    await provider.start(buildTestClient());

    expect(calls, isEmpty);
  });

  test(
    'backgroundService mode starts/stops the native foreground service',
    () async {
      final provider = notificationDeliveryProviderFor(
        NotificationDeliveryMode.backgroundService,
      );
      await provider.start(buildTestClient());
      await provider.stop(buildTestClient());
      expect(calls, [
        'startBackgroundSyncService',
        'stopBackgroundSyncService',
      ]);
    },
  );

  test('fcm mode resolves to the real FCM transport, not a no-op', () {
    expect(
      notificationDeliveryProviderFor(NotificationDeliveryMode.fcm),
      same(fcmDeliveryProvider),
    );
  });

  group('Apple push', () {
    test('resolves to its own provider, not an Android transport', () {
      final provider = notificationDeliveryProviderFor(
        NotificationDeliveryMode.apns,
      );

      expect(provider, isA<ApnsDeliveryProvider>());
      expect(
        provider,
        same(notificationDeliveryProviderFor(NotificationDeliveryMode.apns)),
      );
      for (final other in [
        NotificationDeliveryMode.fcm,
        NotificationDeliveryMode.unifiedPush,
        NotificationDeliveryMode.backgroundService,
      ]) {
        expect(provider, isNot(same(notificationDeliveryProviderFor(other))));
      }
    });

    test('without the native token handler, starting and stopping it touch '
        'nothing', () async {
      final client = _PusherClient();
      final provider = notificationDeliveryProviderFor(
        NotificationDeliveryMode.apns,
      );

      await provider.start(client);
      await provider.stop(client);

      expect(calls, isEmpty);
      expect(client.posted, isEmpty);
      expect(client.deleted, isEmpty);
    });

    test('without the native token handler, retry, recheck and kick-off '
        'leave it alone', () async {
      final client = _PusherClient();

      await retryFailedDelivery(client, NotificationDeliveryMode.apns);
      await recheckDelivery(client, NotificationDeliveryMode.apns);
      await kickOffDeliveryMode(client, NotificationDeliveryMode.apns);

      expect(calls, isEmpty);
      expect(client.posted, isEmpty);
      expect(client.deleted, isEmpty);
    });

    group('once the native token handler exists', () {
      late _PusherClient client;

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        ambientCapabilities = iosCapabilities;
        client = _PusherClient();
        apnsDeliveryProvider.tokenReader = () async => _apnsToken;
        apnsDeliveryProvider.environmentReader = () async => 'development';
        addTearDown(() => apnsDeliveryProvider.stop(client));
        addTearDown(apnsDeliveryProvider.resetEnvironmentForTesting);
      });

      test('kick-off registers it', () async {
        await kickOffDeliveryMode(client, NotificationDeliveryMode.apns);

        expect(client.posted.map((p) => p.appId), [apnsAppId]);
      });

      test('retryFailedDelivery re-registers a failed registration', () async {
        apnsDeliveryProvider.status.value = ApnsStatus.pusherFailed;

        await retryFailedDelivery(client, NotificationDeliveryMode.apns);

        expect(client.posted.map((p) => p.pushkey), [_apnsPushkey]);
      });

      test('retryFailedDelivery leaves a working registration alone', () async {
        apnsDeliveryProvider.status.value = ApnsStatus.ready;

        await retryFailedDelivery(client, NotificationDeliveryMode.apns);

        expect(client.posted, isEmpty);
      });
    });
  });

  test('stopping all delivery still stops background sync', () async {
    SharedPreferences.setMockInitialValues({});

    await stopAllNotificationDelivery(_PusherClient());

    expect(calls, contains('stopBackgroundSyncService'));
  });

  group('stopping all delivery with VoIP rings', () {
    final voip = <MethodCall>[];

    setUp(() {
      voip.clear();
      messenger.setMockMethodCallHandler(voipChannel, (call) async {
        voip.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(nseChannel, (call) async {
        voip.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(voipChannel, null);
        messenger.setMockMethodCallHandler(nseChannel, null);
      });
    });

    test('also closes the call session and wipes the read model', () async {
      ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
      SharedPreferences.setMockInitialValues({
        voipSessionKey: '@me:example.org|PHONE',
      });

      await stopAllNotificationDelivery(_PusherClient());

      expect(voip.map((c) => [c.method, c.arguments]), [
        ['wipe', null],
        [
          'setSession',
          {'signedIn': false},
        ],
      ]);
    });

    test('never touches calls on Android', () async {
      ambientCapabilities = androidCapabilities;
      SharedPreferences.setMockInitialValues({
        voipSessionKey: '@me:example.org|PHONE',
      });

      await stopAllNotificationDelivery(_PusherClient());

      expect(voip, isEmpty);
    });
  });

  test('notificationDeliveryProviderFor returns a stable singleton per mode — '
      '_AuthGate calls it on every rebuild, so a fresh instance each time '
      'would be wasteful but still must behave identically', () {
    expect(
      notificationDeliveryProviderFor(
        NotificationDeliveryMode.backgroundService,
      ),
      same(
        notificationDeliveryProviderFor(
          NotificationDeliveryMode.backgroundService,
        ),
      ),
    );
  });

  test('bindAppStateToPushDelivery reaches both push runners', () async {
    const lock = MethodChannel('zuno/push_wakelock');
    messenger.setMockMethodCallHandler(
      lock,
      (call) async => call.method == 'appInFront' ? false : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(lock, null));

    bindAppStateToPushDelivery(
      currentlyOpenRoomId: () => '!open:example.org',
      isAppSyncing: () => true,
    );

    for (final runner in [
      fcmDeliveryProvider.runner,
      unifiedPushDeliveryProvider.runner,
    ]) {
      expect(runner.currentlyOpenRoomId(), '!open:example.org');
      expect(runner.isAppSyncing(), isTrue);
      expect(await runner.nativeAppInFront(), isFalse);
    }
  });

  group('telling FCM the app takes pushes', () {
    const fcm = MethodChannel('zuno/fcm');
    late List<String> fcmCalls;

    setUp(() {
      fcmCalls = [];
      fcmDeliveryProvider.runner
        ..liveClient = buildTestClient()
        ..currentlyOpenRoomId = (() => null)
        ..isAppSyncing = (() => false);
      addTearDown(() => fcmDeliveryProvider.runner.liveClient = null);
      addTearDown(() => messenger.setMockMethodCallHandler(fcm, null));
    });

    test('happens only once the app state is bound', () async {
      String? openRoomWhenReady;
      bool? syncingWhenReady;
      messenger.setMockMethodCallHandler(fcm, (call) async {
        fcmCalls.add(call.method);
        if (call.method == 'ready') {
          openRoomWhenReady = fcmDeliveryProvider.runner.currentlyOpenRoomId();
          syncingWhenReady = fcmDeliveryProvider.runner.isAppSyncing();
        }
        return true;
      });

      bindAppStateToPushDelivery(
        currentlyOpenRoomId: () => '!ready:example.org',
        isAppSyncing: () => true,
      );
      await pumpEventQueue();

      expect(fcmCalls, ['ready']);
      expect(openRoomWhenReady, '!ready:example.org');
      expect(syncingWhenReady, isTrue);
    });

    test('never happens where FCM is not offered', () async {
      ambientCapabilities = iosCapabilities;
      messenger.setMockMethodCallHandler(fcm, (call) async {
        fcmCalls.add(call.method);
        return true;
      });

      bindAppStateToPushDelivery(
        currentlyOpenRoomId: () => null,
        isAppSyncing: () => false,
      );
      await pumpEventQueue();

      expect(fcmCalls, isEmpty);
    });
  });

  group('routing to the active transport', () {
    late _PusherClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      client = _PusherClient();
      fcmDeliveryProvider
        ..availabilityReader = (() async => FcmAvailability.available)
        ..tokenReader = (() async => 'token-xyz')
        ..tokenDeleter = (() async {});
      addTearDown(() => fcmDeliveryProvider.stop(client));
    });

    test('retryFailedDelivery re-registers a failed FCM transport', () async {
      fcmDeliveryProvider.status.value = FcmStatus.pusherFailed;

      await retryFailedDelivery(client, NotificationDeliveryMode.fcm);

      expect(client.posted.map((p) => p.pushkey), ['token-xyz']);
    });

    test('retryFailedDelivery leaves a healthy transport alone', () async {
      fcmDeliveryProvider.status.value = FcmStatus.ready;

      await retryFailedDelivery(client, NotificationDeliveryMode.fcm);

      expect(client.posted, isEmpty);
    });

    test('recheckDelivery is a no-op for the background service', () async {
      await recheckDelivery(client, NotificationDeliveryMode.backgroundService);

      expect(client.posted, isEmpty);
      expect(calls, isEmpty);
    });
  });
}

class _PusherClient extends Client {
  _PusherClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  final posted = <Pusher>[];

  final deleted = <PusherId>[];

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async {
    posted.add(pusher);
  }

  @override
  Future<void> deletePusher(PusherId pusherId) async {
    deleted.add(pusherId);
  }
}
