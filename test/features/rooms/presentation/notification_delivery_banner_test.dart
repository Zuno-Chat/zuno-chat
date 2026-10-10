import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/rooms/presentation/notification_delivery_banner.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fixed_notifications_allowed.dart';

Widget _wrap(DeliveryFailure? failure) => ProviderScope(
  overrides: [deliveryFailureProvider.overrideWithValue(failure)],
  child: const MaterialApp(home: Scaffold(body: NotificationDeliveryBanner())),
);

void main() {
  testWidgets('shows the failure and exactly one action button', (
    tester,
  ) async {
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
    expect(find.byType(TextButton), findsOneWidget);
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
            fixedNotificationsAllowed(true),
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
  });

  group('a notice and a failure', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        notificationDeliveryModeAutoKey: 'backgroundService',
      });
      prefs = await SharedPreferences.getInstance();
    });

    Future<void> pumpBanner(
      WidgetTester tester,
      DeliveryFailure failure,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            deliveryFailureProvider.overrideWithValue(failure),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationDeliveryBanner()),
          ),
        ),
      );
    }

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
