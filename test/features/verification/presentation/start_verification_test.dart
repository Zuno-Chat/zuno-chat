import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:matrix/encryption.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/features/verification/presentation/start_verification.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/caught_reports.dart';
import 'verification_harness.dart';

const _failed = 'Could not start.';

void main() {
  late ValueNotifier<bool> callerShown;
  late Future<KeyVerification> Function() start;
  late List<Object?> results;

  setUp(() {
    callerShown = ValueNotifier(true);
    results = [];
  });

  tearDown(() => callerShown.dispose());

  Future<void> tapStart(
    WidgetTester tester, {
    bool isOwnDevice = false,
    bool picturesFirst = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: callerShown,
              builder: (_, shown, _) => shown
                  ? Builder(
                      builder: (context) => TextButton(
                        onPressed: () async => results.add(
                          await startAndOpenVerification(
                            context,
                            start,
                            label: 'start test check',
                            failed: _failed,
                            isOwnDevice: isOwnDevice,
                            picturesFirst: picturesFirst,
                          ),
                        ),
                        child: const Text('start'),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await settle(tester);
  }

  testWidgets('opens the check as asked and hands it back once closed', (
    tester,
  ) async {
    final verification = FakeKeyVerification();
    start = () async => verification;

    await tapStart(tester, isOwnDevice: true, picturesFirst: true);

    final page = tester.widget<VerificationPage>(find.byType(VerificationPage));
    expect(page.keyVerification, same(verification));
    expect(page.isOwnDevice, isTrue);
    expect(page.picturesFirst, isTrue);
    expect(results, isEmpty);

    await tester.pageBack();
    await settle(tester);

    expect(results, [same(verification)]);
  });

  testWidgets('a start that fails is reported, says so and opens nothing', (
    tester,
  ) async {
    start = () async => throw StateError('no encryption');

    final reports = await reportsDuring(() => tapStart(tester));

    expect(reports, ['start test check']);
    expect(find.text('$_failed Try again.'), findsOneWidget);
    expect(find.byType(VerificationPage), findsNothing);
    expect(results, [isNull]);
  });

  testWidgets('a start lost to the connection says to check it', (
    tester,
  ) async {
    start = () async => throw ClientException('offline');

    await tapStart(tester);

    expect(find.textContaining(_failed), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsOneWidget);
  });

  testWidgets('a check that started after the caller went away is canceled', (
    tester,
  ) async {
    final gate = Completer<KeyVerification>();
    final verification = FakeKeyVerification();
    start = () => gate.future;

    await tapStart(tester);
    callerShown.value = false;
    await tester.pump();
    gate.complete(verification);
    await settle(tester);

    expect(find.byType(VerificationPage), findsNothing);
    expect(verification.calls, ['cancel(m.user)']);
    expect(results, [isNull]);
  });
}
