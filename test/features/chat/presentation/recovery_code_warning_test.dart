import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/recovery_code_warning.dart';

void main() {
  Future<bool?> pumpWarning(WidgetTester tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  answer = await confirmSendingRecoveryCode(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('the warning says Zuno never asks for the code', (tester) async {
    await pumpWarning(tester);

    expect(find.textContaining('never asks'), findsOneWidget);
    expect(find.text('Send anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('sending anyway is allowed', (tester) async {
    await pumpWarning(tester);

    await tester.tap(find.text('Send anyway'));
    await tester.pumpAndSettle();

    expect(find.text('Send anyway'), findsNothing);
  });

  testWidgets('cancelling keeps the message unsent', (tester) async {
    await pumpWarning(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
