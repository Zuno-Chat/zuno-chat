import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/verification/presentation/incoming_verification.dart';
import 'package:zuno/features/verification/presentation/verification_page.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_matrix.dart';
import 'verification_harness.dart';

void main() {
  late SharedPreferences preferences;
  late BuildContext home;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(
            buildTestClient(userId: '@me:example.org'),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                home = context;
                return const Text('home');
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> arrive(
    WidgetTester tester,
    FakeKeyVerification request, {
    bool isOwnDevice = false,
  }) async {
    unawaited(
      answerIncomingVerification(home, request, isOwnDevice: isOwnDevice),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('can be declined', (tester) async {
    await pumpHome(tester);
    final request = FakeKeyVerification();

    await arrive(tester, request);
    expect(find.text('@bob wants to verify with you.'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(request.calls, ['rejectVerification']);
    expect(find.byType(VerificationPage), findsNothing);
  });

  testWidgets('once accepted, opens the check', (tester) async {
    await pumpHome(tester);
    final request = FakeKeyVerification();

    await arrive(tester, request);
    await tester.tap(find.text('Accept'));
    await settle(tester);

    expect(request.calls, ['acceptVerification']);
    expect(find.byType(VerificationPage), findsOneWidget);
    expect(find.text('Confirm it is them'), findsOneWidget);
  });

  testWidgets('an accept that fails offline says so and opens no check', (
    tester,
  ) async {
    await pumpHome(tester);
    final request = FakeKeyVerification()
      ..sendError = http.ClientException('offline');

    await arrive(tester, request);
    final reports = await reportsDuring(() async {
      await tester.tap(find.text('Accept'));
      await settle(tester);
    });

    expect(request.calls, ['acceptVerification']);
    expect(find.byType(VerificationPage), findsNothing);
    expect(
      find.text('Could not send that. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(reports, ['answer verification']);
  });

  testWidgets('a decline the server refuses says so and reports it', (
    tester,
  ) async {
    await pumpHome(tester);
    final request = FakeKeyVerification()
      ..sendError = StateError('server said no');

    await arrive(tester, request);
    final reports = await reportsDuring(() async {
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
    });

    expect(request.calls, ['rejectVerification']);
    expect(find.text('Could not send that. Try again.'), findsOneWidget);
    expect(find.byType(VerificationPage), findsNothing);
    expect(reports, ['answer verification']);
  });

  testWidgets('from my own other device, opens it as approving a device', (
    tester,
  ) async {
    await pumpHome(tester);
    final request = FakeKeyVerification(userId: '@me:example.org');

    await arrive(tester, request, isOwnDevice: true);
    await tester.tap(find.text('Accept'));
    await settle(tester);

    expect(find.text('Approve this device'), findsOneWidget);
    expect(find.text('Confirm it is them'), findsNothing);
  });

  testWidgets('canceled before an answer, closes and says why', (tester) async {
    await pumpHome(tester);
    final request = FakeKeyVerification();

    await arrive(tester, request);
    request.stopWith('m.user');
    await tester.pumpAndSettle();

    expect(find.text('@bob wants to verify with you.'), findsNothing);
    expect(
      find.textContaining('One of you canceled the check.'),
      findsOneWidget,
    );
    expect(request.calls, isEmpty);
    expect(find.byType(VerificationPage), findsNothing);
  });

  testWidgets('answered on my other device, closes and says so', (
    tester,
  ) async {
    await pumpHome(tester);
    final request = FakeKeyVerification(userId: '@me:example.org');

    await arrive(tester, request, isOwnDevice: true);
    request.stopWith('m.accepted');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Another one of your devices picked this up'),
      findsOneWidget,
    );
    expect(request.calls, isEmpty);
  });

  testWidgets('canceled under another screen, closes and keeps that screen', (
    tester,
  ) async {
    await pumpHome(tester);
    final request = FakeKeyVerification();
    await arrive(tester, request);
    final prompt = find.text('@bob wants to verify with you.');
    unawaited(
      Navigator.of(tester.element(prompt)).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('On top')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    request.stopWith('m.user');
    await tester.pumpAndSettle();

    expect(find.text('On top'), findsOneWidget);
    expect(
      find.text('@bob wants to verify with you.', skipOffstage: false),
      findsNothing,
    );
    expect(request.calls, isEmpty);
  });

  testWidgets('already stopped when it arrives, shows nothing', (tester) async {
    await pumpHome(tester);
    final request = FakeKeyVerification()..canceled = true;

    await arrive(tester, request);

    expect(find.text('@bob wants to verify with you.'), findsNothing);
    expect(request.calls, isEmpty);
  });
}
