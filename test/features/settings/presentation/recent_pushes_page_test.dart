import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/push_diagnostics_report.dart';
import 'package:zuno/core/push/push_diagnostics_source.dart';
import 'package:zuno/core/push/recent_pushes.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/recent_pushes_page.dart';

import '../../../helpers/platform_capabilities.dart';

class _Source implements PushDiagnosticsSource {
  _Source(this.pushes, {this.fails = false});

  final List<RecentPush> pushes;
  final bool fails;

  @override
  Future<List<RecentPush>> recentPushes(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async {
    if (fails) throw Exception('unreadable');
    return pushes;
  }

  @override
  Future<PushDiagnosticsInputs> load(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) => throw UnimplementedError();

  @override
  Future<PushTestOutcome> sendTest() => throw UnimplementedError();
}

class _FixedMode extends NotificationDeliveryModeNotifier {
  @override
  NotificationDeliveryMode build() => NotificationDeliveryMode.apns;
}

Future<void> _pump(WidgetTester tester, _Source source) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pushDiagnosticsSourceProvider.overrideWithValue(source),
        platformCapabilitiesProvider.overrideWithValue(iosCapabilities),
        notificationDeliveryModeProvider.overrideWith(_FixedMode.new),
      ],
      child: const MaterialApp(home: RecentPushesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the newest ten with a time, flagging late ones', (
    tester,
  ) async {
    final now = DateTime.now();
    await _pump(
      tester,
      _Source([
        RecentPush(at: now, summary: 'Shown. Arrived after 2 min', late: true),
        for (var i = 1; i < 12; i++)
          RecentPush(
            at: now.subtract(Duration(minutes: i)),
            summary: 'Push $i',
          ),
      ]),
    );

    expect(find.text('Shown. Arrived after 2 min'), findsOneWidget);
    expect(find.text('Push 9'), findsOneWidget);
    expect(find.text('Push 10'), findsNothing);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(9));
  });

  testWidgets('says None yet when there are none', (tester) async {
    await _pump(tester, _Source(const []));

    expect(find.text('None yet'), findsOneWidget);
  });

  testWidgets('says None yet when the log cannot be read', (tester) async {
    await _pump(tester, _Source(const [], fails: true));

    expect(find.text('None yet'), findsOneWidget);
  });

  testWidgets('an older push is labeled with its day', (tester) async {
    await _pump(
      tester,
      _Source([
        RecentPush(
          at: DateTime.now().subtract(const Duration(days: 1)),
          summary: 'Shown',
        ),
      ]),
    );

    expect(find.textContaining('Yesterday, '), findsOneWidget);
  });
}
