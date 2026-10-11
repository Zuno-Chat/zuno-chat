import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_status.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_status_line.dart';
import 'package:zuno/features/calls/presentation/call_status_widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: zunoDarkTheme,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  for (final (status, text) in [
    (CallStatus.calling, 'Calling…'),
    (CallStatus.connecting, 'Connecting…'),
    (CallStatus.waiting, 'Waiting for the other side to join…'),
  ]) {
    testWidgets('$status says "$text" and claims no lock', (tester) async {
      await pump(tester, CallStatusLine(status: status));

      expect(find.text(text), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });
  }

  testWidgets('encrypting shows the lock, then the advice after 8 seconds', (
    tester,
  ) async {
    await pump(tester, const CallStatusLine(status: CallStatus.encrypting));

    expect(find.text('Encrypting…'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text(EncryptingLabel.hint), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    expect(
      find.text('Still encrypting. If this continues, hang up and try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text(EncryptingLabel.hint)).textAlign,
      TextAlign.center,
    );
  });

  testWidgets('an encrypted call shows the lock and a clock that ticks on its '
      'own', (tester) async {
    var now = DateTime(2026, 9, 20, 12, 0, 41);
    var outerBuilds = 0;
    await pump(
      tester,
      Builder(
        builder: (context) {
          outerBuilds++;
          return CallStatusLine(
            status: CallStatus.talking,
            talkingSince: DateTime(2026, 9, 20, 12),
            now: () => now,
          );
        },
      ),
    );

    expect(find.text('0:41'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Encrypted')), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:42'), findsOneWidget);
    expect(outerBuilds, 1);
  });

  testWidgets('the clock stops when the line goes away', (tester) async {
    await pump(
      tester,
      CallStatusLine(
        status: CallStatus.talking,
        talkingSince: DateTime(2026, 9, 20, 12),
      ),
    );
    await pump(tester, const SizedBox());
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the ticking clock repaints only itself', (tester) async {
    await pump(
      tester,
      CallStatusLine(
        status: CallStatus.talking,
        talkingSince: DateTime(2026, 9, 20, 12),
      ),
    );

    final clock = tester.renderObject(
      find.descendant(
        of: find.byType(CallTimer),
        matching: find.byType(RepaintBoundary),
      ),
    );
    expect(clock.isRepaintBoundary, isTrue);
    expect(
      find.descendant(of: find.byType(CallTimer), matching: find.byType(Text)),
      findsOneWidget,
    );
  });
}
