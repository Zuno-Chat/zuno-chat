import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/status_message.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget message) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: message)));

  testWidgets('a busy message spins with its title and no icon', (
    tester,
  ) async {
    await pump(tester, const StatusMessage.busy(title: 'Waiting'));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('a settled message shows its icon, body and action', (
    tester,
  ) async {
    await pump(
      tester,
      StatusMessage(
        icon: Icons.check_circle_outline,
        title: 'Done',
        body: 'All set.',
        action: FilledButton(onPressed: () {}, child: const Text('Close')),
      ),
    );

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('All set.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);
  });

  testWidgets('leaves out a missing body and action', (tester) async {
    await pump(
      tester,
      const StatusMessage(icon: Icons.lock_outline, title: 'Locked'),
    );

    expect(find.byType(Text), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
