import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/abuse_report.dart';
import 'package:zuno/features/reports/presentation/report_sheet.dart';

void main() {
  bool? result;

  Future<void> openSheet(
    WidgetTester tester, {
    required SendReport onSend,
    String sendLabel = 'Send report',
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReportSheet(
                  context,
                  title: 'Report message',
                  explanation: 'The report goes to Zuno.',
                  sendLabel: sendLabel,
                  onSend: onSend,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton sendButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('shows the title, the explanation and every reason', (
    tester,
  ) async {
    await openSheet(tester, onSend: (_, _) async {});

    expect(find.text('Report message'), findsOneWidget);
    expect(find.text('The report goes to Zuno.'), findsOneWidget);
    for (final reason in ReportReason.values) {
      expect(find.text(reason.label), findsOneWidget);
    }
  });

  testWidgets('cannot be sent before a reason is chosen', (tester) async {
    await openSheet(tester, onSend: (_, _) async {});

    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('something else needs a note', (tester) async {
    await openSheet(tester, onSend: (_, _) async {});

    await tester.tap(find.text('Something else'));
    await tester.pump();
    expect(sendButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'odd links');
    await tester.pump();
    expect(sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('sends the chosen reason and note, then closes', (tester) async {
    ReportReason? sentReason;
    String? sentNote;
    await openSheet(
      tester,
      onSend: (reason, note) async {
        sentReason = reason;
        sentNote = note;
      },
    );

    await tester.tap(find.text('Harassment'));
    await tester.enterText(find.byType(TextField), 'threats');
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(sentReason, ReportReason.harassment);
    expect(sentNote, 'threats');
    expect(result, isTrue);
    expect(find.text('Report message'), findsNothing);
  });

  testWidgets('a failed send stays open and says so', (tester) async {
    await openSheet(tester, onSend: (_, _) async => throw Exception('offline'));

    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(find.text('The report was not sent. Try again.'), findsOneWidget);
    expect(find.text('Report message'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);
    expect(result, isNull);
  });

  testWidgets('dismissing sends nothing', (tester) async {
    var sent = false;
    await openSheet(tester, onSend: (_, _) async => sent = true);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(sent, isFalse);
    expect(result, isFalse);
  });

  testWidgets('uses the given send label', (tester) async {
    await openSheet(
      tester,
      onSend: (_, _) async {},
      sendLabel: 'Report and decline',
    );

    expect(find.text('Report and decline'), findsOneWidget);
  });
}
