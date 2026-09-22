import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/errors/feedback.dart';
import 'package:zuno/features/feedback/presentation/feedback_sheet.dart';

void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required Future<void> Function(String message) onSend,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFeedbackSheet(context, onSend: onSend),
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

  testWidgets('says where the feedback goes and that there is no reply', (
    tester,
  ) async {
    await openSheet(tester, onSend: (_) async {});

    expect(find.textContaining('reporting service'), findsOneWidget);
    expect(find.textContaining('app version'), findsOneWidget);
    expect(find.textContaining('no reply'), findsOneWidget);
  });

  testWidgets('cannot send an empty or blank message', (tester) async {
    await openSheet(tester, onSend: (_) async {});

    expect(sendButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('sends the trimmed message, closes and confirms', (tester) async {
    String? sent;
    await openSheet(tester, onSend: (message) async => sent = message);

    await tester.enterText(find.byType(TextField), '  Calls drop on wifi ');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(sent, 'Calls drop on wifi');
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Feedback sent.'), findsOneWidget);
  });

  testWidgets('cannot send twice while a send is in flight', (tester) async {
    final gate = Completer<void>();
    var sends = 0;
    await openSheet(
      tester,
      onSend: (_) {
        sends++;
        return gate.future;
      },
    );

    await tester.enterText(find.byType(TextField), 'Idea');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(sendButton(tester).onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();

    expect(sends, 1);
  });

  testWidgets('a failed send keeps the sheet open with the text intact', (
    tester,
  ) async {
    await openSheet(tester, onSend: (_) async => throw const FeedbackNotSent());

    await tester.enterText(find.byType(TextField), 'Calls drop on wifi');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Calls drop on wifi'), findsOneWidget);
    expect(
      find.text('Feedback not sent. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Feedback sent.'), findsNothing);
    expect(sendButton(tester).onPressed, isNotNull);
  });
}
