import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/features/rooms/presentation/notification_delivery_banner.dart';

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
}
