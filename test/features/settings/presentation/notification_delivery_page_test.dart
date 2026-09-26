import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';
import '../../../helpers/platform_capabilities.dart';

class _CountingUnifiedPush extends FakeUnifiedPush {
  int distributorReads = 0;

  @override
  Future<String?> getDistributor() async {
    distributorReads++;
    return null;
  }
}

class _FixedDeliveryModeNotifier extends NotificationDeliveryModeNotifier {
  _FixedDeliveryModeNotifier(this._mode);
  final NotificationDeliveryMode _mode;

  @override
  NotificationDeliveryMode build() => _mode;
}

Future<void> _pumpPage(
  WidgetTester tester,
  NotificationDeliveryMode mode, {
  PlatformCapabilities? capabilities,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      matrixClientProvider.overrideWithValue(buildTestClient()),
      notificationDeliveryModeProvider.overrideWith(
        () => _FixedDeliveryModeNotifier(mode),
      ),
      if (capabilities != null)
        platformCapabilitiesProvider.overrideWithValue(capabilities),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: NotificationDeliveryPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    UnifiedPushPlatform.instance = FakeUnifiedPush();
  });

  testWidgets(
    'the Google services row is selectable, not a disabled placeholder',
    (tester) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(find.text('Google services').first);
      await tester.pumpAndSettle();

      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Google services').last,
      );
      expect(row.enabled, isTrue);
    },
  );

  testWidgets('shows the current method and explains the choices', (
    tester,
  ) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expect(find.text('Delivery method'), findsOneWidget);
    expect(
      find.text(NotificationDeliveryMode.backgroundService.label),
      findsOneWidget,
    );
    expect(find.textContaining('while Zuno is closed'), findsOneWidget);
    expect(find.text('Background data'), findsOneWidget);
  });

  testWidgets('FCM offers the battery exemption too, since it keeps a '
      'sleeping device from holding notifications back', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.text('Unrestricted battery usage'), findsOneWidget);
    expect(find.textContaining('can hold notifications back'), findsOneWidget);
  });

  group('autostart', () {
    late List<String> calls;

    void mockBackgroundSync({required bool hasAutostart}) {
      calls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('zuno/background_sync');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'hasAutostartSettings' => hasAutostart,
          'isIgnoringBatteryOptimizations' => false,
          'isBackgroundDataRestricted' => false,
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    testWidgets('gets a row on devices that stop closed apps from starting', (
      tester,
    ) async {
      mockBackgroundSync(hasAutostart: true);
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(find.text('Autostart'));
      await tester.pump();

      expect(calls, contains('openAutostartSettings'));
    });

    testWidgets('has no row elsewhere', (tester) async {
      mockBackgroundSync(hasAutostart: false);
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(find.text('Autostart'), findsNothing);
    });
  });

  testWidgets('but there is one for UnifiedPush', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

    await tester.scrollUntilVisible(
      find.text('Unrestricted battery usage'),
      200,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Unrestricted battery usage'), findsOneWidget);
  });

  group('the methods on offer', () {
    testWidgets('Android offers its three methods and nothing else', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      await tester.tap(find.text('Delivery method'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      for (final label in [
        'Google services',
        'UnifiedPush',
        'Background sync',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.text('Apple push'), findsNothing);
    });

    testWidgets('Android keeps explaining what each method needs', (
      tester,
    ) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(
        find.text(
          'How messages and calls reach you while Zuno is closed. '
          'Background sync needs no setup. UnifiedPush needs a distributor '
          'app, such as ntfy, installed. Google services needs Google Play '
          'services.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the picker offers only what this platform has', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.unifiedPush,
        capabilities: capabilitiesLike(
          androidCapabilities,
          deliveryModes: const [
            NotificationDeliveryMode.unifiedPush,
            NotificationDeliveryMode.backgroundService,
          ],
        ),
      );

      await tester.tap(find.text('Delivery method'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Google services')),
        findsNothing,
      );
    });

    testWidgets('with one method there is no picker at all', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
      );

      expect(find.text('Delivery method'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('Apple push'), findsOneWidget);
      expect(
        find.text(NotificationDeliveryMode.apns.description),
        findsOneWidget,
      );
      expect(find.textContaining('UnifiedPush'), findsNothing);

      await tester.tap(find.text('Apple push'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('battery and background data guidance', () {
    tearDown(() {
      unifiedPushDeliveryProvider.distributorBatteryRestricted.value = false;
      unifiedPushDeliveryProvider.savedDistributor = null;
    });

    testWidgets('iOS shows none of it', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
      );

      expect(find.text('Unrestricted battery usage'), findsNothing);
      expect(find.text('Background data'), findsNothing);
      expect(find.text('Autostart'), findsNothing);
    });

    testWidgets('no battery row where the platform has no battery exemption, '
        'even for a method that would show one', (tester) async {
      final noExemption = capabilitiesLike(
        androidCapabilities,
        batteryExemption: false,
      );
      for (final mode in androidCapabilities.deliveryModes) {
        await tester.pumpWidget(const SizedBox());
        await _pumpPage(tester, mode, capabilities: noExemption);

        expect(
          find.text('Unrestricted battery usage'),
          findsNothing,
          reason: mode.name,
        );
      }
    });

    testWidgets('no distributor battery row where the platform has no '
        'battery exemption', (tester) async {
      unifiedPushDeliveryProvider
        ..savedDistributor = 'io.heckel.ntfy'
        ..distributorBatteryRestricted.value = true;

      await _pumpPage(
        tester,
        NotificationDeliveryMode.unifiedPush,
        capabilities: capabilitiesLike(
          androidCapabilities,
          batteryExemption: false,
        ),
      );

      expect(find.text('ntfy battery', skipOffstage: false), findsNothing);
    });

    testWidgets('Android still names a battery-restricted distributor', (
      tester,
    ) async {
      unifiedPushDeliveryProvider
        ..savedDistributor = 'io.heckel.ntfy'
        ..distributorBatteryRestricted.value = true;

      await _pumpPage(tester, NotificationDeliveryMode.unifiedPush);

      expect(find.text('ntfy battery', skipOffstage: false), findsOneWidget);
    });

    testWidgets('no background data row where the platform does not restrict '
        'it', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.backgroundService,
        capabilities: capabilitiesLike(
          androidCapabilities,
          backgroundDataRestriction: false,
        ),
      );

      expect(find.text('Background data'), findsNothing);
      expect(find.text('Unrestricted battery usage'), findsOneWidget);
    });
  });

  group('the UnifiedPush distributor lookup', () {
    late _CountingUnifiedPush unifiedPush;

    setUp(() {
      unifiedPush = _CountingUnifiedPush();
      UnifiedPushPlatform.instance = unifiedPush;
    });

    testWidgets('runs where UnifiedPush is on offer', (tester) async {
      await _pumpPage(tester, NotificationDeliveryMode.fcm);

      expect(unifiedPush.distributorReads, greaterThan(0));
    });

    testWidgets('never runs where it is not', (tester) async {
      await _pumpPage(
        tester,
        NotificationDeliveryMode.apns,
        capabilities: iosCapabilities,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(unifiedPush.distributorReads, 0);
    });
  });
}
