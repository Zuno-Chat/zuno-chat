import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:zuno/core/push/voip/voip_registration.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/delivery_failure_action.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/fake_voip_registration.dart';
import '../../../helpers/fixed_delivery_mode.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      notificationDeliveryModeAutoKey: 'backgroundService',
    });
    prefs = await SharedPreferences.getInstance();
    UnifiedPushPlatform.instance = FakeUnifiedPush();
  });

  List<String> recordRegistrations() {
    final asked = <String>[];
    final fcm = fcmDeliveryProvider.notificationsAllowed;
    final unifiedPush = unifiedPushDeliveryProvider.notificationsAllowed;
    final apns = apnsDeliveryProvider.notificationsAllowed;
    fcmDeliveryProvider.notificationsAllowed = () async {
      asked.add('fcm');
      return false;
    };
    unifiedPushDeliveryProvider.notificationsAllowed = () async {
      asked.add('unifiedPush');
      return false;
    };
    apnsDeliveryProvider.notificationsAllowed = () async {
      asked.add('apns');
      return false;
    };
    addTearDown(() {
      fcmDeliveryProvider
        ..notificationsAllowed = fcm
        ..runner.liveClient = null;
      unifiedPushDeliveryProvider
        ..notificationsAllowed = unifiedPush
        ..runner.liveClient = null;
      apnsDeliveryProvider.notificationsAllowed = apns;
    });
    return asked;
  }

  Future<void> tapAct(WidgetTester tester) async {
    await tester.tap(find.text('Act'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Future<ProviderContainer> pumpActor(
    WidgetTester tester,
    DeliveryFailureAction action, {
    NotificationDeliveryMode? mode,
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        matrixClientProvider.overrideWithValue(buildTestClient()),
        if (mode != null) fixedDeliveryMode(mode),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => runDeliveryFailureAction(
                  context,
                  ref,
                  DeliveryFailure(
                    message: 'Something is wrong',
                    action: action,
                  ),
                ),
                child: const Text('Act'),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<ProviderContainer> act(
    WidgetTester tester,
    DeliveryFailureAction action, {
    NotificationDeliveryMode? mode,
    List<Override> overrides = const [],
  }) async {
    final container = await pumpActor(
      tester,
      action,
      mode: mode,
      overrides: overrides,
    );
    await tapAct(tester);
    return container;
  }

  testWidgets('acting on a failure brings it back if it was dismissed', (
    tester,
  ) async {
    const failure = DeliveryFailure(
      message: 'Could not set up notifications on this device',
      action: DeliveryFailureAction.retry,
    );
    final container = await pumpActor(
      tester,
      DeliveryFailureAction.retry,
      mode: NotificationDeliveryMode.backgroundService,
      overrides: [deliveryFailureProvider.overrideWithValue(failure)],
    );
    container.read(dismissedDeliveryFailureProvider.notifier).dismiss(failure);

    await tapAct(tester);

    expect(container.read(dismissedDeliveryFailureProvider), isNull);
  });

  testWidgets('Open settings retires the switched-method notice and opens '
      'the delivery page', (tester) async {
    await act(tester, DeliveryFailureAction.openSettings);
    await tester.pumpAndSettle();

    expect(prefs.getString(notificationDeliveryModeAutoKey), isNull);
    expect(find.byType(NotificationDeliveryPage), findsOneWidget);
  });

  group('Open settings on a distributor', () {
    tearDown(() => unifiedPushDeliveryProvider.savedDistributor = null);

    testWidgets('opens that app', (tester) async {
      final backgroundSync = recordMethodChannel('zuno/background_sync');
      unifiedPushDeliveryProvider.savedDistributor = 'io.heckel.ntfy';

      await act(tester, DeliveryFailureAction.openDistributorSettings);

      expect(backgroundSync.calls.map((c) => [c.method, c.arguments]), [
        [
          'openAppSettings',
          {'package': 'io.heckel.ntfy'},
        ],
      ]);
    });

    testWidgets('with none saved has nothing to open', (tester) async {
      final backgroundSync = recordMethodChannel('zuno/background_sync');

      await act(tester, DeliveryFailureAction.openDistributorSettings);

      expect(backgroundSync.calls, isEmpty);
    });
  });

  testWidgets('Switch to UnifiedPush saves the choice and looks for a '
      'distributor', (tester) async {
    addTearDown(
      () => unifiedPushDeliveryProvider.status.value = UnifiedPushStatus.idle,
    );

    await act(tester, DeliveryFailureAction.switchToUnifiedPush);

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
    await act(tester, DeliveryFailureAction.switchToBackgroundService);

    expect(
      prefs.getString('settings.notification_delivery_mode'),
      'backgroundService',
    );
  });

  for (final action in [
    DeliveryFailureAction.updatePlayServices,
    DeliveryFailureAction.turnOnPlayServices,
  ]) {
    testWidgets('${action.name} asks Android to fix Google Play services', (
      tester,
    ) async {
      final fcm = recordMethodChannel('zuno/fcm');

      await act(tester, action);

      expect(fcm.methods.first, 'fixPlayServices');
    });
  }

  group('Retry', () {
    for (final (name, mode, PlatformCapabilities capabilities, registers) in [
      (
        'with Google services registers this device again',
        NotificationDeliveryMode.fcm,
        androidCapabilities,
        ['fcm'],
      ),
      (
        'with UnifiedPush asks the distributor again',
        NotificationDeliveryMode.unifiedPush,
        androidCapabilities,
        ['unifiedPush'],
      ),
      (
        'with Apple push registers this device again',
        NotificationDeliveryMode.apns,
        iosCapabilities,
        ['apns'],
      ),
      (
        'with background sync has nothing to register',
        NotificationDeliveryMode.backgroundService,
        androidCapabilities,
        <String>[],
      ),
    ]) {
      testWidgets(name, (tester) async {
        ambientCapabilities = capabilities;
        final asked = recordRegistrations();

        await act(tester, DeliveryFailureAction.retry, mode: mode);

        expect(asked, registers);
      });
    }

    testWidgets('on call setup registers for calls again', (tester) async {
      final voip = FakeVoipRegistration();
      final container = await act(
        tester,
        DeliveryFailureAction.retryCalls,
        overrides: [voipRegistrationProvider.overrideWithValue(voip)],
      );

      expect(voip.registered, [container.read(matrixClientProvider)]);
    });
  });
}
