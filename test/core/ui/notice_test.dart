import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/notice.dart';

import '../../helpers/caught_reports.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Chat')),
      ),
    );
    return tester.element(find.text('Chat'));
  }

  testWidgets('a successful action says so when asked and reports nothing', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    late bool done;
    final reports = await reportsDuring(() async {
      done = await attempt(
        context,
        () async {},
        label: 'mute chat',
        failed: 'Chat not muted.',
        succeeded: 'Chat muted',
      );
    });
    await tester.pump();

    expect(done, isTrue);
    expect(reports, isEmpty);
    expect(find.text('Chat muted'), findsOneWidget);
  });

  testWidgets('a failure while offline is reported and asks to check the '
      'connection', (tester) async {
    final context = await pumpHost(tester);
    final l10n = context.l10n;
    late bool done;
    final reports = await reportsDuring(() async {
      done = await attempt(
        context,
        () => throw const SocketException('offline'),
        label: 'mute chat',
        failed: 'Chat not muted.',
        succeeded: 'Chat muted',
      );
    });
    await tester.pump();

    expect(done, isFalse);
    expect(reports, ['mute chat']);
    expect(
      find.text(l10n.errorsFailedCheckConnection('Chat not muted.')),
      findsOneWidget,
    );
    expect(find.text('Chat muted'), findsNothing);
  });

  testWidgets('any other failure says what failed and to try again', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    await reportsDuring(
      () => attempt(
        context,
        () => throw StateError('server said no'),
        label: 'mute chat',
        failed: 'Chat not muted.',
      ),
    );
    await tester.pump();

    expect(find.text('Chat not muted. Try again.'), findsOneWidget);
  });

  testWidgets('copy puts the text on the clipboard and says so', (
    tester,
  ) async {
    final writes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final context = await pumpHost(tester);

    await ScaffoldMessenger.of(context).copy('!room', copied: 'Copied');
    await tester.pump();

    expect(writes, ['!room']);
    expect(find.text('Copied'), findsOneWidget);
  });
}
