import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_unified_push.dart';

class _FixedDeliveryModeNotifier extends NotificationDeliveryModeNotifier {
  _FixedDeliveryModeNotifier(this._mode);
  final NotificationDeliveryMode _mode;

  @override
  NotificationDeliveryMode build() => _mode;
}

Future<void> _pumpPage(
  WidgetTester tester,
  NotificationDeliveryMode mode,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      matrixClientProvider.overrideWithValue(buildTestClient()),
      notificationDeliveryModeProvider.overrideWith(
        () => _FixedDeliveryModeNotifier(mode),
      ),
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
}
