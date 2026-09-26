import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/background_sync_delivery_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';

import '../../helpers/fake_matrix.dart';

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

    test('starting and stopping it touch nothing', () async {
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

    test('retry, recheck and kick-off leave it alone', () async {
      final client = _PusherClient();

      await retryFailedDelivery(client, NotificationDeliveryMode.apns);
      await recheckDelivery(client, NotificationDeliveryMode.apns);
      await kickOffDeliveryMode(client, NotificationDeliveryMode.apns);

      expect(calls, isEmpty);
      expect(client.posted, isEmpty);
      expect(client.deleted, isEmpty);
    });
  });

  test('stopping all delivery still stops background sync', () async {
    SharedPreferences.setMockInitialValues({});

    await stopAllNotificationDelivery(_PusherClient());

    expect(calls, contains('stopBackgroundSyncService'));
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

  test('bindAppStateToPushDelivery reaches both push runners', () {
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
    }
  });

  group('routing to the active transport', () {
    const playServices = MethodChannel('zuno/play_services');
    late _PusherClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      messenger.setMockMethodCallHandler(
        playServices,
        (call) async => call.method == 'checkPlayServices' ? 'AVAILABLE' : null,
      );
      client = _PusherClient();
      fcmDeliveryProvider
        ..tokenReader = (() async => 'token-xyz')
        ..tokenDeleter = (() async {});
      addTearDown(() async {
        await fcmDeliveryProvider.stop(client);
        messenger.setMockMethodCallHandler(playServices, null);
      });
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
