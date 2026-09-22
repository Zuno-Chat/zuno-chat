import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/recovery_code.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/features/settings/presentation/change_password_dialog.dart';
import 'package:zuno/features/settings/presentation/recovery_code_screens.dart';
import 'package:zuno/features/settings/presentation/uia_password_prompt.dart';

void main() {
  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  TextField fieldLabelled(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label));

  AutofillGroup groupAround(WidgetTester tester, String label) =>
      tester.widget<AutofillGroup>(
        find.ancestor(of: field(label), matching: find.byType(AutofillGroup)),
      );

  List<bool> savesOffered(WidgetTester tester) => [
    for (final call in tester.testTextInput.log)
      if (call.method == 'TextInput.finishAutofillContext')
        call.arguments as bool,
  ];

  group('the account password prompt', () {
    Future<void> openPrompt(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => askPasswordForUia(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('tells the password manager it wants the password', (
      tester,
    ) async {
      await openPrompt(tester);

      expect(fieldLabelled(tester, 'Password').autofillHints, [
        AutofillHints.password,
      ]);
    });

    testWidgets('never asks to save what was typed into it', (tester) async {
      await openPrompt(tester);

      expect(
        groupAround(tester, 'Password').onDisposeAction,
        AutofillContextAction.cancel,
      );

      await tester.enterText(field('Password'), 'correct horse battery staple');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(savesOffered(tester), [false]);
    });
  });

  group('changing the password', () {
    Future<List<(String, String)>> openDialog(
      WidgetTester tester, {
      Object? failure,
    }) async {
      final submitted = <(String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ChangePasswordDialog(
                  username: 'alice',
                  onSubmit: (current, next) async {
                    submitted.add((current, next));
                    if (failure != null) throw failure;
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return submitted;
    }

    Future<void> fill(
      WidgetTester tester, {
      String next = 'a quiet blue harbour',
    }) async {
      await tester.enterText(field('Current password'), 'old horse battery');
      await tester.enterText(field('New password'), next);
      await tester.enterText(field('Confirm new password'), next);
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
    }

    testWidgets('each field says what it holds', (tester) async {
      await openDialog(tester);

      final username = fieldLabelled(tester, 'Username');
      expect(username.readOnly, isTrue);
      expect(username.controller?.text, 'alice');
      expect(username.autofillHints, [AutofillHints.username]);
      expect(fieldLabelled(tester, 'Current password').autofillHints, [
        AutofillHints.password,
      ]);
      for (final label in ['New password', 'Confirm new password']) {
        expect(fieldLabelled(tester, label).autofillHints, [
          AutofillHints.newPassword,
        ], reason: label);
      }
    });

    testWidgets('offers the new password for saving once the server took it', (
      tester,
    ) async {
      final submitted = await openDialog(tester);

      await fill(tester);

      expect(submitted, [('old horse battery', 'a quiet blue harbour')]);
      expect(savesOffered(tester).first, isTrue);
      expect(find.byType(ChangePasswordDialog), findsNothing);
    });

    testWidgets('a refused change stays open and offers nothing to save', (
      tester,
    ) async {
      await openDialog(tester, failure: Exception('refused'));

      await fill(tester);

      expect(find.text('Password not changed. Try again.'), findsOneWidget);
      expect(find.byType(ChangePasswordDialog), findsOneWidget);
      expect(savesOffered(tester), isEmpty);
    });

    testWidgets('cancelling offers nothing to save', (tester) async {
      await openDialog(tester);

      await tester.enterText(field('New password'), 'a quiet blue harbour');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(savesOffered(tester), [false]);
    });

    testWidgets('a new password the sign-up form would refuse is refused', (
      tester,
    ) async {
      final submitted = await openDialog(tester);

      await fill(tester, next: 'password12345');

      expect(submitted, isEmpty);
      expect(find.text('That is built on a common password'), findsOneWidget);
    });
  });

  group('entering a recovery code', () {
    testWidgets('can be filled from the password manager it was saved to', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryWordlistProvider.overrideWith(
              (ref) async => RecoveryWordlist.parse('alpha\nbravo'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RecoveryCodeEntryField(
                controller: TextEditingController(),
                error: null,
                busy: false,
                onSubmit: () {},
              ),
            ),
          ),
        ),
      );

      expect(fieldLabelled(tester, 'Recovery code').autofillHints, [
        AutofillHints.password,
      ]);
      expect(
        groupAround(tester, 'Recovery code').onDisposeAction,
        AutofillContextAction.cancel,
      );
    });
  });
}
