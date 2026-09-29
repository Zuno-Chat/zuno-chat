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
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/apns_pusher.dart';
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
          message: 'Google services needs an update',
          action: DeliveryFailureAction.fixGoogleServices,
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

  testWidgets('renders exactly one action button, never a choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const DeliveryFailure(
          message: 'The server did not accept this device',
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
    ambientCapabilities = capabilitiesLike(
      iosCapabilities,
      apnsRegistration: true,
    );
    final client = _PusherClient();
    apnsDeliveryProvider
      ..tokenReader = (() async => _apnsToken)
      ..notificationsAllowed = (() async => true)
      ..status.value = ApnsStatus.pusherFailed;
    addTearDown(() => apnsDeliveryProvider.stop(client));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deliveryFailureProvider.overrideWithValue(
            const DeliveryFailure(
              message: 'The server did not accept this device',
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

    testWidgets('Fix Google services asks Android to fix them', (tester) async {
      recordChannel(tester, 'zuno/play_services');
      await pumpBanner(
        tester,
        const DeliveryFailure(
          message: 'Google services needs an update',
          action: DeliveryFailureAction.fixGoogleServices,
        ),
      );

      await act(tester, 'Fix Google services');

      expect(channelCalls, ['zuno/play_services fixPlayServices']);
    });

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
}
