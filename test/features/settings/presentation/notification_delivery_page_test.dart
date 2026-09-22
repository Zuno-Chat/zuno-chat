import 'package:flutter/material.dart';
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

  testWidgets('no battery-exemption row for FCM', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.fcm);

    expect(find.textContaining('battery', findRichText: true), findsNothing);
    expect(find.text('Unrestricted battery usage'), findsNothing);
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
