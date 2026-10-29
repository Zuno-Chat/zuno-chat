import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/form_sheet.dart';

import '../../helpers/caught_reports.dart';

void main() {
  bool? result;

  Future<void> openSheet(
    WidgetTester tester, {
    required Future<void> Function(String text) send,
    Widget Function(BuildContext context, bool sending)? above,
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showFormSheet(
                  context,
                  sent: 'Sent.',
                  builder: (_) => FormSheet(
                    title: 'Tell us',
                    explanation: 'It goes to the team.',
                    fieldLabel: 'Message',
                    maxLines: 4,
                    maxLength: 100,
                    sendLabel: 'Send',
                    failed: 'Not sent.',
                    debugLabel: 'send note',
                    canSend: (text) => text.trim().isNotEmpty,
                    send: send,
                    above: above,
                  ),
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

  testWidgets('shows the title, the explanation and the extra content', (
    tester,
  ) async {
    await openSheet(
      tester,
      send: (_) async {},
      above: (_, _) => const Text('Reasons'),
    );

    expect(find.text('Tell us'), findsOneWidget);
    expect(find.text('It goes to the team.'), findsOneWidget);
    expect(find.text('Reasons'), findsOneWidget);
  });

  testWidgets('sends the trimmed text, closes and says it was sent', (
    tester,
  ) async {
    String? sent;
    await openSheet(tester, send: (text) async => sent = text);

    expect(sendButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  hello ');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(sent, 'hello');
    expect(result, isTrue);
    expect(find.text('Tell us'), findsNothing);
    expect(find.text('Sent.'), findsOneWidget);
  });

  testWidgets('locks the form while sending', (tester) async {
    final gate = Completer<void>();
    bool? sendingSeen;
    await openSheet(
      tester,
      send: (_) => gate.future,
      above: (_, sending) {
        sendingSeen = sending;
        return const SizedBox();
      },
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sendButton(tester).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(sendingSeen, isTrue);

    gate.complete();
    await tester.pumpAndSettle();
  });

  Future<List<String>> sendFailing(WidgetTester tester) =>
      reportsDuring(() async {
        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pump();
        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();
      });

  testWidgets('a failed send stays open with the text, says what failed '
      'and reports it', (tester) async {
    await openSheet(tester, send: (_) async => throw StateError('refused'));

    final reports = await sendFailing(tester);

    expect(find.text('Not sent. Try again.'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);
    expect(find.text('Sent.'), findsNothing);
    expect(result, isNull);
    expect(reports, ['send note']);
  });

  testWidgets('a send that fails offline asks to check the connection', (
    tester,
  ) async {
    await openSheet(
      tester,
      send: (_) async => throw const SocketException('offline'),
    );

    await sendFailing(tester);

    expect(
      find.text('Not sent. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('sending again clears the last failure', (tester) async {
    final gate = Completer<void>();
    var fail = true;
    await openSheet(
      tester,
      send: (_) async {
        if (fail) throw StateError('refused');
        await gate.future;
      },
    );
    await sendFailing(tester);

    fail = false;
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(find.text('Not sent. Try again.'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('dismissing sends nothing and says nothing', (tester) async {
    var sent = false;
    await openSheet(tester, send: (_) async => sent = true);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(sent, isFalse);
    expect(result, isFalse);
    expect(find.text('Sent.'), findsNothing);
  });
}
