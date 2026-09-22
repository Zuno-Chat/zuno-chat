import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/notification_delivery_page.dart';
import 'package:zuno/features/settings/presentation/notifications_settings_page.dart';

import '../../../helpers/card_layout.dart';
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
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
      child: const MaterialApp(home: NotificationsSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    UnifiedPushPlatform.instance = FakeUnifiedPush();
  });

  testWidgets('every setting sits on a card', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expectEveryRowOnACard();
  });

  testWidgets('the Delivery row names the method in use', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Delivery'),
    );
    expect(
      (row.subtitle! as Text).data,
      NotificationDeliveryMode.backgroundService.label,
    );
  });

  testWidgets('transport rows are off this page, whatever the method', (
    tester,
  ) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expect(find.text('Delivery method'), findsNothing);
    expect(find.text('Unrestricted battery usage'), findsNothing);
    expect(find.text('Background data'), findsNothing);
    expect(find.text('Status'), findsNothing);
  });

  testWidgets('everyday rows stay', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    expect(find.text('Enable notifications'), findsOneWidget);
    expect(find.text('Mentions only'), findsOneWidget);
    expect(find.text('Ringtone'), findsOneWidget);
  });

  testWidgets('tapping Delivery opens the delivery page', (tester) async {
    await _pumpPage(tester, NotificationDeliveryMode.backgroundService);

    await tester.tap(find.widgetWithText(ListTile, 'Delivery'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationDeliveryPage), findsOneWidget);
    expect(find.text('Delivery method'), findsOneWidget);
  });
}
