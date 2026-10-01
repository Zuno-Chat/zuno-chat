import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/apns_pusher.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_pusher.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/rooms/presentation/notification_delivery_banner.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/platform_capabilities.dart';

const _apnsToken =
    'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';

class _PusherClient extends Client {
  _PusherClient() : super('test', database: FakeDatabaseApi()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }

  final posted = <Pusher>[];

  @override
  Future<void> postPusher(Pusher pusher, {bool? append}) async =>
      posted.add(pusher);

  @override
  Future<void> deletePusher(PusherId pusherId) async {}
}

class _FixedMode extends NotificationDeliveryModeNotifier {
  _FixedMode(this.mode);
  final NotificationDeliveryMode mode;

  @override
  NotificationDeliveryMode build() => mode;
}

class _NotificationsAllowed extends NotificationsAllowedNotifier {
  @override
  bool? build() => true;
}

Widget _wrap(DeliveryFailure? failure) => ProviderScope(
  overrides: [deliveryFailureProvider.overrideWithValue(failure)],
  child: const MaterialApp(home: Scaffold(body: NotificationDeliveryBanner())),
);

void main() {
  testWidgets('shows the failure and its one action', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const DeliveryFailure(
          message: 'This device does not have Google services',
          action: DeliveryFailureAction.switchToUnifiedPush,
        ),
      ),
    );

    expect(
      find.text('This device does not have Google services'),
      findsOneWidget,
    );
    expect(find.text('Switch to UnifiedPush'), findsOneWidget);
  });

  testWidgets('shows nothing at all when delivery is healthy', (tester) async {
    await tester.pumpWidget(_wrap(null));

    expect(find.byType(NotificationDeliveryBanner), findsOneWidget);
    expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);
  });

  testWidgets('dismissing hides it for this session', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const DeliveryFailure(
          message: 'Google Play services needs an update',
          action: DeliveryFailureAction.updatePlayServices,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);
  });

  testWidgets(
    'reappears when the failure changes to a different one while dismissed',
    (tester) async {
      const failureA = DeliveryFailure(
        message: 'Could not set up notifications on this device',
        action: DeliveryFailureAction.retry,
      );
      const failureB = DeliveryFailure(
        message: 'This device does not have Google services',
        action: DeliveryFailureAction.switchToUnifiedPush,
      );

      await tester.pumpWidget(_wrap(failureA));
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);

      await tester.pumpWidget(_wrap(failureB));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('deliveryFailureBanner')),
        findsOneWidget,
      );
      expect(
        find.text('This device does not have Google services'),
        findsOneWidget,
      );
    },
  );

  testWidgets('on a narrow phone a long action sits under the message, '
      'which keeps its width', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        const DeliveryFailure(
          message: 'Google Play services is turned off',
          action: DeliveryFailureAction.turnOnPlayServices,
        ),
      ),
    );

    final message = tester.getRect(
      find.text('Google Play services is turned off'),
    );
    final action = tester.getRect(find.text('Turn on Google Play services'));
    expect(action.top, greaterThanOrEqualTo(message.bottom));
    expect(message.width, greaterThan(200));
  });

  testWidgets('renders exactly one action button, never a choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const DeliveryFailure(
          message: 'Could not set up notifications on this device',
          action: DeliveryFailureAction.retry,
        ),
      ),
    );

    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Retry on Apple push registers this device again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    ambientCapabilities = iosCapabilities;
    final client = _PusherClient();
    final tokenReader = apnsDeliveryProvider.tokenReader;
    final notificationsAllowed = apnsDeliveryProvider.notificationsAllowed;
    apnsDeliveryProvider
      ..tokenReader = (() async => _apnsToken)
      ..notificationsAllowed = (() async => true)
      ..status.value = ApnsStatus.pusherFailed;
    addTearDown(() async {
      await apnsDeliveryProvider.stop(client);
      apnsDeliveryProvider
        ..tokenReader = tokenReader
        ..notificationsAllowed = notificationsAllowed;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deliveryFailureProvider.overrideWithValue(
            const DeliveryFailure(
              message: 'Could not set up notifications on this device',
              action: DeliveryFailureAction.retry,
            ),
          ),
          notificationDeliveryModeProvider.overrideWith(
            () => _FixedMode(NotificationDeliveryMode.apns),
          ),
          matrixClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationDeliveryBanner()),
        ),
      ),
    );
    await tester.tap(find.text('Retry'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(client.posted.map((p) => p.appId), [apnsAppId]);
  });

  group('on a device without Google Play services', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'settings.notification_delivery_mode': 'fcm',
        'settings.notification_delivery_mode_chosen': true,
      });
      prefs = await SharedPreferences.getInstance();
      fcmDeliveryProvider.status.value = FcmStatus.playServicesUnavailable;
      addTearDown(() => fcmDeliveryProvider.status.value = FcmStatus.idle);
    });

    Future<void> pumpBanner(
      WidgetTester tester, {
      required bool distributorInstalled,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            matrixClientProvider.overrideWithValue(buildTestClient()),
            notificationsAllowedProvider.overrideWith(
              _NotificationsAllowed.new,
            ),
            unifiedPushDistributorInstalledProvider.overrideWithValue(
              AsyncData(distributorInstalled),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationDeliveryBanner()),
          ),
        ),
      );
    }

    testWidgets('with no distributor installed, offers background sync '
        'directly, and it takes one tap', (tester) async {
      await pumpBanner(tester, distributorInstalled: false);

      expect(
        find.text('This device does not have Google Play services'),
        findsOneWidget,
      );
      expect(find.text('Switch to UnifiedPush'), findsNothing);

      await tester.tap(find.text('Use background sync'));
      await tester.pump();

      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'backgroundService',
      );
      expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);
    });

    testWidgets('with a distributor installed, offers UnifiedPush', (
      tester,
    ) async {
      await pumpBanner(tester, distributorInstalled: true);

      expect(find.text('Switch to UnifiedPush'), findsOneWidget);
      expect(find.text('Use background sync'), findsNothing);
    });
  });

  group('each action', () {
    late SharedPreferences prefs;
    late List<String> channelCalls;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        notificationDeliveryModeAutoKey: 'backgroundService',
      });
      prefs = await SharedPreferences.getInstance();
      channelCalls = [];
      UnifiedPushPlatform.instance = FakeUnifiedPush();
    });

    void recordChannel(WidgetTester tester, String name) {
      final channel = MethodChannel(name);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        channelCalls.add('$name ${call.method} ${call.arguments ?? ''}'.trim());
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    Future<void> pumpBanner(
      WidgetTester tester,
      DeliveryFailure failure, {
      NotificationDeliveryMode? mode,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            matrixClientProvider.overrideWithValue(buildTestClient()),
            deliveryFailureProvider.overrideWithValue(failure),
            if (mode != null)
              notificationDeliveryModeProvider.overrideWith(
                () => _FixedMode(mode),
              ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationDeliveryBanner()),
          ),
        ),
      );
    }

    List<String> recordRegistrations() {
      final asked = <String>[];
      final fcm = fcmDeliveryProvider.notificationsAllowed;
      final unifiedPush = unifiedPushDeliveryProvider.notificationsAllowed;
      fcmDeliveryProvider.notificationsAllowed = () async {
        asked.add('fcm');
        return false;
      };
      unifiedPushDeliveryProvider.notificationsAllowed = () async {
        asked.add('unifiedPush');
        return false;
      };
      addTearDown(() {
        fcmDeliveryProvider
          ..notificationsAllowed = fcm
          ..runner.liveClient = null;
        unifiedPushDeliveryProvider
          ..notificationsAllowed = unifiedPush
          ..runner.liveClient = null;
      });
      return asked;
    }

    Future<void> act(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    testWidgets('Open settings clears the notice and opens delivery', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'Zuno switched to background sync',
          action: DeliveryFailureAction.openSettings,
          notice: true,
        ),
      );

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(prefs.getString(notificationDeliveryModeAutoKey), isNull);
      expect(find.byType(NotificationDeliveryPage), findsOneWidget);
    });

    testWidgets('Open settings on a distributor opens that app', (
      tester,
    ) async {
      recordChannel(tester, 'zuno/background_sync');
      unifiedPushDeliveryProvider.savedDistributor = 'io.heckel.ntfy';
      addTearDown(() => unifiedPushDeliveryProvider.savedDistributor = null);
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'ntfy is asleep',
          action: DeliveryFailureAction.openDistributorSettings,
        ),
      );

      await act(tester, 'Open settings');

      expect(channelCalls, hasLength(1));
      expect(channelCalls.single, contains('openAppSettings'));
      expect(channelCalls.single, contains('io.heckel.ntfy'));
    });

    testWidgets('without a distributor there is nothing to open', (
      tester,
    ) async {
      recordChannel(tester, 'zuno/background_sync');
      unifiedPushDeliveryProvider.savedDistributor = null;
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'ntfy is asleep',
          action: DeliveryFailureAction.openDistributorSettings,
        ),
      );

      await act(tester, 'Open settings');

      expect(channelCalls, isEmpty);
    });

    testWidgets('Switch to UnifiedPush saves the choice and looks for a '
        'distributor', (tester) async {
      addTearDown(
        () => unifiedPushDeliveryProvider.status.value = UnifiedPushStatus.idle,
      );
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'This device does not have Google services',
          action: DeliveryFailureAction.switchToUnifiedPush,
        ),
      );

      await act(tester, 'Switch to UnifiedPush');

      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'unifiedPush',
      );
      expect(
        unifiedPushDeliveryProvider.status.value,
        UnifiedPushStatus.noDistributorFound,
      );
    });

    testWidgets('Use background sync saves that choice', (tester) async {
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'No distributor found',
          action: DeliveryFailureAction.switchToBackgroundService,
        ),
      );

      await act(tester, 'Use background sync');

      expect(
        prefs.getString('settings.notification_delivery_mode'),
        'backgroundService',
      );
    });

    for (final (action, message, label) in [
      (
        DeliveryFailureAction.updatePlayServices,
        'Google Play services needs an update',
        'Update Google Play services',
      ),
      (
        DeliveryFailureAction.turnOnPlayServices,
        'Google Play services is turned off',
        'Turn on Google Play services',
      ),
    ]) {
      testWidgets('$label asks Android for exactly that', (tester) async {
        recordChannel(tester, 'zuno/fcm');
        await pumpBanner(
          tester,
          DeliveryFailure(message: message, action: action),
        );

        await act(tester, label);

        expect(channelCalls, ['zuno/fcm fixPlayServices']);
      });
    }

    for (final (mode, provider) in [
      (NotificationDeliveryMode.fcm, 'fcm'),
      (NotificationDeliveryMode.unifiedPush, 'unifiedPush'),
    ]) {
      testWidgets('Retry registers again through ${mode.name}', (tester) async {
        final asked = recordRegistrations();
        await pumpBanner(
          tester,
          const DeliveryFailure(
            message: 'Could not set up notifications on this device',
            action: DeliveryFailureAction.retry,
          ),
          mode: mode,
        );

        await act(tester, 'Retry');

        expect(asked, [provider]);
      });
    }

    testWidgets('Retry on background sync has nothing to register', (
      tester,
    ) async {
      final asked = recordRegistrations();
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'Could not set up notifications on this device',
          action: DeliveryFailureAction.retry,
        ),
        mode: NotificationDeliveryMode.backgroundService,
      );

      await act(tester, 'Retry');

      expect(asked, isEmpty);
    });

    testWidgets('a notice is calm, and dismissing it clears it for good', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'Zuno switched to background sync',
          action: DeliveryFailureAction.openSettings,
          notice: true,
        ),
      );

      final colors = Theme.of(
        tester.element(find.byType(NotificationDeliveryBanner)),
      ).colorScheme;
      final banner = tester.widget<Material>(
        find.byKey(const ValueKey('deliveryFailureBanner')),
      );
      expect(banner.color, colors.secondaryContainer);
      expect(find.byType(AttentionStripe), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(prefs.getString(notificationDeliveryModeAutoKey), isNull);
      expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);
    });

    testWidgets('a failure stands out and dismissing it keeps any notice', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'Could not set up notifications on this device',
          action: DeliveryFailureAction.retry,
        ),
      );

      final colors = Theme.of(
        tester.element(find.byType(NotificationDeliveryBanner)),
      ).colorScheme;
      final banner = tester.widget<Material>(
        find.byKey(const ValueKey('deliveryFailureBanner')),
      );
      expect(banner.color, colors.errorContainer);
      expect(find.byType(AttentionStripe), findsOneWidget);

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(
        prefs.getString(notificationDeliveryModeAutoKey),
        'backgroundService',
      );
    });
  });

  group('after this device is removed as a push target', () {
    const notRegistered = 'This device is not registered for notifications';
    late _PusherClient client;

    Future<void> pumpBanner(
      WidgetTester tester,
      NotificationDeliveryMode mode,
    ) async {
      SharedPreferences.setMockInitialValues({
        'settings.notification_delivery_mode': mode.name,
        'settings.notification_delivery_mode_chosen': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            matrixClientProvider.overrideWithValue(client),
            notificationsAllowedProvider.overrideWith(
              _NotificationsAllowed.new,
            ),
            unifiedPushDistributorInstalledProvider.overrideWithValue(
              const AsyncData(true),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationDeliveryBanner()),
          ),
        ),
      );
    }

    Future<void> retry(WidgetTester tester) async {
      await tester.tap(find.text('Retry'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    setUp(() => client = _PusherClient());

    testWidgets('with Google services it says so, and Retry registers this '
        'device again', (tester) async {
      final availabilityReader = fcmDeliveryProvider.availabilityReader;
      final tokenReader = fcmDeliveryProvider.tokenReader;
      final tokenDeleter = fcmDeliveryProvider.tokenDeleter;
      final notificationsAllowed = fcmDeliveryProvider.notificationsAllowed;
      fcmDeliveryProvider
        ..availabilityReader = (() async => FcmAvailability.available)
        ..tokenReader = (() async => 'fcm-token-abc')
        ..tokenDeleter = (() async {})
        ..notificationsAllowed = (() async => true);
      addTearDown(() async {
        await fcmDeliveryProvider.stop(client);
        fcmDeliveryProvider
          ..availabilityReader = availabilityReader
          ..tokenReader = tokenReader
          ..tokenDeleter = tokenDeleter
          ..notificationsAllowed = notificationsAllowed
          ..runner.liveClient = null;
      });
      await tester.runAsync(() async {
        await fcmDeliveryProvider.registerNow(client);
        await fcmDeliveryProvider.remove(client);
      });

      await pumpBanner(tester, NotificationDeliveryMode.fcm);

      expect(find.text(notRegistered), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await retry(tester);

      expect(client.posted.map((p) => p.appId), [fcmAppId, fcmAppId]);
      expect(fcmDeliveryProvider.status.value, FcmStatus.ready);
      expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);
    });

    testWidgets('with UnifiedPush it says so, and Retry asks the distributor '
        'again', (tester) async {
      final unifiedPush = _RegisteringUnifiedPush();
      final platform = UnifiedPushPlatform.instance;
      final notificationsAllowed =
          unifiedPushDeliveryProvider.notificationsAllowed;
      final batteryCheck =
          unifiedPushDeliveryProvider.distributorIgnoresBatteryOptimizations;
      UnifiedPushPlatform.instance = unifiedPush;
      unifiedPushDeliveryProvider
        ..notificationsAllowed = (() async => true)
        ..distributorIgnoresBatteryOptimizations = ((_) async => true);
      addTearDown(() async {
        await unifiedPushDeliveryProvider.stop(client);
        UnifiedPushPlatform.instance = platform;
        unifiedPushDeliveryProvider
          ..notificationsAllowed = notificationsAllowed
          ..distributorIgnoresBatteryOptimizations = batteryCheck
          ..savedDistributor = null
          ..status.value = UnifiedPushStatus.idle
          ..runner.liveClient = null;
      });
      await tester.runAsync(() => unifiedPushDeliveryProvider.remove(client));

      await pumpBanner(tester, NotificationDeliveryMode.unifiedPush);

      expect(find.text(notRegistered), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await retry(tester);

      expect(unifiedPush.registered, 1);
      expect(
        unifiedPushDeliveryProvider.status.value,
        UnifiedPushStatus.registering,
      );
      expect(find.byKey(const ValueKey('deliveryFailureBanner')), findsNothing);
    });
  });
}

class _RegisteringUnifiedPush extends FakeUnifiedPush {
  int registered = 0;

  @override
  Future<List<String>> getDistributors(List<String> features) async => [
    'io.heckel.ntfy',
  ];

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async => registered++;
}
