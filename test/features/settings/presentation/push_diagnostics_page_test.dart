import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/push_diagnostics_data.dart';
import 'package:zuno/core/push/push_diagnostics_report.dart';
import 'package:zuno/core/push/push_diagnostics_source.dart';
import 'package:zuno/features/settings/presentation/push_diagnostics_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/platform_capabilities.dart';

final _ios = capabilitiesLike(
  iosCapabilities,
  pushDiagnostics: true,
  voipRing: true,
  nseNotifications: true,
);
final _now = DateTime(2026, 10, 2, 12);

PushDiagnosticsInputs _inputs() => PushDiagnosticsInputs(
  capabilities: _ios,
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
  reach: ServerReach.reachable,
  pushers: const [],
  currentPushkey: 'cHVzaGtleQ==',
  expectedGateway: Uri.parse('https://zuno.im/_matrix/push/v1/notify'),
);

class _FakeSource implements PushDiagnosticsSource {
  _FakeSource({this.outcome = PushTestOutcome.sent, this.fails = false});

  PushTestOutcome outcome;
  bool fails;
  int loads = 0;
  int tests = 0;

  @override
  Future<PushDiagnosticsInputs> load(PlatformCapabilities capabilities) async {
    loads++;
    if (fails) throw Exception('no answer');
    return _inputs();
  }

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
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pushDiagnosticsSourceProvider.overrideWithValue(source),
        platformCapabilitiesProvider.overrideWithValue(_ios),
      ],
      child: MaterialApp(home: PushDiagnosticsPage(share: share)),
    ),
  );
  await tester.pumpAndSettle();
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
}
