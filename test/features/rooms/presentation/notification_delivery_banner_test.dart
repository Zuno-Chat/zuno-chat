import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/rooms/presentation/notification_delivery_banner.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

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

class _ApplePushMode extends NotificationDeliveryModeNotifier {
  @override
  NotificationDeliveryMode build() => NotificationDeliveryMode.apns;
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
      ..tokenReader = (() async => 'apns-token')
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
          notificationDeliveryModeProvider.overrideWith(_ApplePushMode.new),
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

    expect(client.posted.map((p) => p.appId), ['im.zuno.chat.ios']);
  });
}
