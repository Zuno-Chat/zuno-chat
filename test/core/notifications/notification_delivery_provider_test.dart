import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/background_sync_delivery_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/push/pusher_info.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';
import 'package:zuno/core/push/voip/voip_channel.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/pusher_recording_client.dart';

const _apnsToken =
    'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
const _apnsPushkey = 'obLD1KGyw9ShssPUobLD1KGyw9ShssPUobLD1KGyw9Q=';

PusherInfo _pusher({required String appId, required String pushkey}) =>
    PusherInfo(
      appId: appId,
      pushkey: pushkey,
      appDisplayName: 'Zuno Chat',
      deviceDisplayName: 'Zuno on Android',
      kind: 'http',
      lang: 'en',
    );

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

  group('Apple push', () {
    test('without the native token handler, retry, recheck and kick-off '
        'leave it alone', () async {
      final client = PusherRecordingClient();

      await retryFailedDelivery(client, NotificationDeliveryMode.apns);
      await recheckDelivery(client, NotificationDeliveryMode.apns);
      await kickOffDeliveryMode(client, NotificationDeliveryMode.apns);

      expect(calls, isEmpty);
      expect(client.posted, isEmpty);
      expect(client.deleted, isEmpty);
    });

    group('once the native token handler exists', () {
      late PusherRecordingClient client;

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        ambientCapabilities = iosCapabilities;
        client = PusherRecordingClient();
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

    await stopAllNotificationDelivery(PusherRecordingClient());

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

      await stopAllNotificationDelivery(PusherRecordingClient());

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

      await stopAllNotificationDelivery(PusherRecordingClient());

      expect(voip, isEmpty);
    });
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
    late PusherRecordingClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      client = PusherRecordingClient();
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
  });

  group("the running transport's own pusher and last error", () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fcmDeliveryProvider
        ..availabilityReader = (() async => FcmAvailability.available)
        ..tokenReader = (() async => 'fcm-token-abc')
        ..tokenDeleter = (() async {});
      await fcmDeliveryProvider.registerNow(PusherRecordingClient());
    });

    tearDown(() async {
      await fcmDeliveryProvider.stop(PusherRecordingClient());
      unifiedPushDeliveryProvider.lastPusherError = null;
    });

    test('a transport with nothing registered claims no pusher as its own', () {
      expect(
        currentPushkeyFor(NotificationDeliveryMode.backgroundService),
        isNull,
      );
      final groups = groupPushers([
        _pusher(appId: fcmAppId, pushkey: 'fcm-token-abc'),
      ], currentPushkeyFor(NotificationDeliveryMode.backgroundService));
      expect(groups.currentSession, isNull);
    });

    test(
      'the last error shown is the running transport, not the other one',
      () {
        unifiedPushDeliveryProvider.lastPusherError =
            'ntfy refused the endpoint';

        expect(lastPusherErrorFor(NotificationDeliveryMode.fcm), isNull);
        expect(
          lastPusherErrorFor(NotificationDeliveryMode.unifiedPush),
          'ntfy refused the endpoint',
        );
      },
    );

    group('Apple push', () {
      tearDown(() async {
        await apnsDeliveryProvider.stop(PusherRecordingClient());
        apnsDeliveryProvider.lastPusherError = null;
        apnsDeliveryProvider.resetEnvironmentForTesting();
      });

      test('this session is identified by its device token, and its pusher is '
          'never an "other push target"', () async {
        ambientCapabilities = iosCapabilities;
        apnsDeliveryProvider
          ..tokenReader = (() async => _apnsToken)
          ..notificationsAllowed = (() async => true)
          ..environmentReader = (() async => 'development');
        await apnsDeliveryProvider.registerNow(PusherRecordingClient());

        final groups = groupPushers([
          _pusher(appId: apnsAppId, pushkey: _apnsPushkey),
          _pusher(appId: fcmAppId, pushkey: 'fcm-token-abc'),
        ], currentPushkeyFor(NotificationDeliveryMode.apns));

        expect(groups.currentSession?.pushkey, _apnsPushkey);
        expect(groups.others.single.appId, fcmAppId);
      });

      test('its last error is shown, not the Android one', () {
        apnsDeliveryProvider.lastPusherError = 'M_FORBIDDEN';

        expect(
          lastPusherErrorFor(NotificationDeliveryMode.apns),
          'M_FORBIDDEN',
        );
        expect(lastPusherErrorFor(NotificationDeliveryMode.fcm), isNull);
      });
    });
  });
}
