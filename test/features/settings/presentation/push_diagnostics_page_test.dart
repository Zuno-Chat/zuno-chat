import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/push_diagnostics_data.dart';
import 'package:zuno/core/push/push_diagnostics_report.dart';
import 'package:zuno/core/push/push_diagnostics_source.dart';
import 'package:zuno/core/push/recent_pushes.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/push_diagnostics_page.dart';
import 'package:zuno/features/settings/presentation/recent_pushes_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/platform_capabilities.dart';

final _ios = capabilitiesLike(
  iosCapabilities,
  pushDiagnostics: true,
  voipRing: true,
  nseNotifications: true,
);
final _now = DateTime(2026, 10, 2, 12);

PushDiagnosticsInputs _inputs({
  PlatformCapabilities? capabilities,
  ServerReach reach = ServerReach.reachable,
}) => PushDiagnosticsInputs(
  capabilities: capabilities ?? _ios,
  now: _now,
  appVersion: '1.2.0 (build 2)',
  snapshot: PushDiagnosticsSnapshot(
    settings: const {'authorization': 'authorized', 'alert': 'enabled'},
    environment: 'production',
    extensionLastRun: _now.subtract(const Duration(minutes: 2)),
    extensionVersion: '1.2.0 (2)',
    extensionLog: const ['shown for @alice:zuno.im'],
  ),
  voip: const VoipDeviceStatus(
    hasToken: true,
    callKit: true,
    environment: 'production',
    kid: 7,
  ),
  health: const ServerHealth(voipRegistered: true, voipKid: 7),
  reach: reach,
  pushers: const [],
  currentPushkey: 'cHVzaGtleQ==',
  expectedGateway: Uri.parse('https://zuno.im/_matrix/push/v1/notify'),
);

class _FakeSource implements PushDiagnosticsSource {
  _FakeSource({
    this.outcome = PushTestOutcome.sent,
    this.fails = false,
    this.capabilities,
    this.reach = ServerReach.reachable,
  });

  final PlatformCapabilities? capabilities;
  final ServerReach reach;
  PushTestOutcome outcome;
  bool fails;
  int loads = 0;
  int tests = 0;

  @override
  Future<PushDiagnosticsInputs> load(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async {
    loads++;
    if (fails) throw Exception('no answer');
    return _inputs(capabilities: capabilities, reach: reach);
  }

  @override
  Future<List<RecentPush>> recentPushes(
    PlatformCapabilities capabilities,
    NotificationDeliveryMode mode,
  ) async => const [];

  @override
  Future<PushTestOutcome> sendTest() async {
    tests++;
    return outcome;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeSource source, {
  Future<void> Function(String text)? share,
  PlatformCapabilities? capabilities,
  NotificationDeliveryMode mode = NotificationDeliveryMode.apns,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(800, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pushDiagnosticsSourceProvider.overrideWithValue(source),
        platformCapabilitiesProvider.overrideWithValue(capabilities ?? _ios),
        notificationDeliveryModeProvider.overrideWith(() => _FixedMode(mode)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: PushDiagnosticsPage(share: share)),
    ),
  );
  await tester.pumpAndSettle();
}

class _FixedMode extends NotificationDeliveryModeNotifier {
  _FixedMode(this._mode);
  final NotificationDeliveryMode _mode;

  @override
  NotificationDeliveryMode build() => _mode;
}

void main() {
  testWidgets('every section sits on a card', (tester) async {
    await _pump(tester, _FakeSource());

    expectEveryRowOnACard();
    for (final title in [
      'Permission',
      'This device',
      'Calls',
      'Notification extension',
      'Delivery',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Allowed'), findsOneWidget);
  });

  testWidgets('a sent test says what to expect', (tester) async {
    final source = _FakeSource();
    await _pump(tester, source);

    await tester.tap(find.text('Send a test notification'));
    await tester.pumpAndSettle();

    expect(source.tests, 1);
    expect(
      find.text(
        'Test notification sent. If nothing arrives within a minute, '
        'notifications are not reaching this device.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('too many tests says to wait', (tester) async {
    await _pump(tester, _FakeSource(outcome: PushTestOutcome.rateLimited));

    await tester.tap(find.text('Send a test notification'));
    await tester.pumpAndSettle();

    expect(
      find.text('Too many tests in the last hour. Try again later.'),
      findsOneWidget,
    );
  });

  testWidgets('a test that could not be sent says to check the connection', (
    tester,
  ) async {
    await _pump(tester, _FakeSource(outcome: PushTestOutcome.failed));

    await tester.tap(find.text('Send a test notification'));
    await tester.pumpAndSettle();

    expect(
      find.text('Test not sent. Check your connection and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('sharing hands over the report without IDs', (tester) async {
    String? shared;
    await _pump(tester, _FakeSource(), share: (text) async => shared = text);

    await tester.tap(find.text('Share diagnostics'));
    await tester.pumpAndSettle();

    expect(shared, startsWith('Zuno notification diagnostics'));
    expect(shared, isNot(contains('@alice:zuno.im')));
  });

  testWidgets('pulling down checks again', (tester) async {
    final source = _FakeSource();
    await _pump(tester, source);

    await tester.fling(find.text('Permission'), const Offset(0, 1500), 1000);
    await tester.pumpAndSettle();

    expect(source.loads, 2);
  });

  testWidgets('a check that fails says so instead of loading forever', (
    tester,
  ) async {
    await _pump(tester, _FakeSource(fails: true));

    expect(find.text('Loading…'), findsNothing);
    expect(
      find.text('Could not check. Pull down to try again.'),
      findsOneWidget,
    );
  });

  testWidgets('the hub ends with Recent pushes and Push target', (
    tester,
  ) async {
    await _pump(tester, _FakeSource());

    expect(find.widgetWithText(ListTile, 'Recent pushes'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Push target'), findsOneWidget);

    await tester.tap(find.text('Recent pushes'));
    await tester.pumpAndSettle();

    expect(find.byType(RecentPushesPage), findsOneWidget);
  });

  testWidgets('Android on UnifiedPush has no Recent pushes row', (
    tester,
  ) async {
    final android = capabilitiesLike(
      androidCapabilities,
      pushDiagnostics: true,
    );
    await _pump(
      tester,
      _FakeSource(capabilities: android),
      capabilities: android,
      mode: NotificationDeliveryMode.unifiedPush,
    );

    expect(find.text('Recent pushes'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Push target'), findsOneWidget);
    expect(find.text('Notifications'), findsWidgets);
  });

  testWidgets('a server without the push module offers no test', (
    tester,
  ) async {
    final source = _FakeSource(reach: ServerReach.notInstalled);
    await _pump(tester, source);

    final row = find.widgetWithText(ListTile, 'Send a test notification');
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    expect(
      find.descendant(
        of: row,
        matching: find.text('Not available on this server'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a test the server cannot run says so', (tester) async {
    await _pump(tester, _FakeSource(outcome: PushTestOutcome.notAvailable));

    await tester.tap(find.text('Send a test notification'));
    await tester.pumpAndSettle();

    expect(
      find.text('Test notifications are not available on this server.'),
      findsOneWidget,
    );
  });

  testWidgets('background sync offers no test', (tester) async {
    final android = capabilitiesLike(
      androidCapabilities,
      pushDiagnostics: true,
    );
    await _pump(
      tester,
      _FakeSource(capabilities: android, reach: ServerReach.notInstalled),
      capabilities: android,
      mode: NotificationDeliveryMode.backgroundService,
    );

    final row = find.widgetWithText(ListTile, 'Send a test notification');
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    expect(
      find.descendant(
        of: row,
        matching: find.text('Not available with background sync'),
      ),
      findsOneWidget,
    );
  });
}
