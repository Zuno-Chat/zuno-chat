import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/features/verification/presentation/verification_request_dialog.dart';

import 'verification_harness.dart';

void main() {
  testWidgets('a request that stopped before the dialog appeared closes it', (
    tester,
  ) async {
    final request = FakeKeyVerification()..canceled = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  VerificationRequestDialog(keyVerification: request),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(VerificationRequestDialog), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(request.onUpdate, isNull);
  });
}
