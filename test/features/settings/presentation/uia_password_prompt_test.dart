import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/auth/uia_cancel.dart';
import 'package:zuno/core/security/prepared_uia_password.dart';
import 'package:zuno/features/settings/presentation/uia_password_prompt.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_sign_in_browser.dart';
import '../../../helpers/uia_challenge.dart';

void main() {
  late Client client;
  late List<String> tried;
  late List<String> opened;
  late Future<void> outcome;
  Object? failure;

  setUp(() {
    client = buildTestClient(userId: '@alice:example.org');
    tried = [];
    failure = null;
  });

  Future<void> answering(
    WidgetTester tester, {
    String title = 'Confirm your password',
    String? Function()? prepared,
    Future<void> Function(AuthenticationData? auth)? request,
  }) async {
    opened = mockSignInBrowser(tester);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(),
        ),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    final sub = client.onUiaRequest.stream.listen(
      (uia) => answerUia(
        context,
        uia,
        userId: client.userID!,
        title: title,
        preparedPassword: prepared,
      ),
    );
    addTearDown(sub.cancel);
    outcome = client
        .uiaRequestBackground<void>(
          request ??
              (auth) async {
                if (auth == null) throw uiaPasswordChallenge();
                final password = (auth as AuthenticationPassword).password;
                tried.add(password);
                if (password != 'right') {
                  throw uiaPasswordChallenge(errcode: 'M_FORBIDDEN');
                }
              },
        )
        .catchError((Object e) => failure = e);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  String? errorShown(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration!.errorText;

  testWidgets('asks once, with no error, and finishes on the right '
      'password', (tester) async {
    await answering(tester);

    expect(find.text('Confirm your password'), findsOneWidget);
    expect(errorShown(tester), isNull);

    await enter(tester, 'right');
    await outcome;

    expect(tried, ['right']);
    expect(failure, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a wrong password asks again and says it was wrong', (
    tester,
  ) async {
    await answering(tester);

    await enter(tester, 'wrong');

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(errorShown(tester), 'Wrong password.');

    await enter(tester, 'right');
    await outcome;

    expect(tried, ['wrong', 'right']);
    expect(failure, isNull);
  });

  testWidgets('keeps saying so after a second wrong password', (tester) async {
    await answering(tester);

    await enter(tester, 'wrong');
    await enter(tester, 'still wrong');

    expect(errorShown(tester), 'Wrong password.');
    expect(tried, ['wrong', 'still wrong']);
  });

  testWidgets('a fresh request starts without the error', (tester) async {
    await answering(tester);
    await enter(tester, 'wrong');
    await enter(tester, 'right');
    await outcome;

    unawaited(
      client.uiaRequestBackground<void>((auth) async {
        if (auth == null) throw uiaPasswordChallenge();
      }),
    );
    await tester.pumpAndSettle();

    expect(errorShown(tester), isNull);
  });

  testWidgets('keeps the title it was given', (tester) async {
    await answering(tester, title: 'Confirm your password to delete');

    expect(find.text('Confirm your password to delete'), findsOneWidget);
  });

  testWidgets('Cancel ends the request as cancelled', (tester) async {
    await answering(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await outcome;

    expect(tried, isEmpty);
    expect(failure.toString(), contains('canceled'));
  });

  testWidgets('an empty password counts as cancelling', (tester) async {
    await answering(tester);

    await enter(tester, '');
    await outcome;

    expect(tried, isEmpty);
    expect(failure.toString(), contains('canceled'));
  });

  testWidgets('a prepared password goes first without asking', (tester) async {
    await answering(
      tester,
      prepared: (PreparedUiaPassword()..prepare('right')).take,
    );
    await outcome;

    expect(tried, ['right']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a prepared password that is wrong asks, saying so', (
    tester,
  ) async {
    await answering(
      tester,
      prepared: (PreparedUiaPassword()..prepare('wrong')).take,
    );

    expect(tried, ['wrong']);
    expect(errorShown(tester), 'Wrong password.');
  });

  testWidgets('a next step Zuno cannot answer ends the request as a failure, '
      'not a cancel or a wrong password', (tester) async {
    await answering(
      tester,
      request: (auth) async {
        if (auth == null) throw uiaPasswordChallenge();
        tried.add((auth as AuthenticationPassword).password);
        throw uiaPasswordChallenge(
          stages: ['m.login.password', 'm.login.terms'],
          completed: ['m.login.password'],
        );
      },
    );

    await enter(tester, 'right');
    await outcome;

    expect(tried, ['right']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(failure, isA<UnanswerableUiaStages>());
    expect(isUiaCancel(failure!), isFalse);
  });

  group('a step approved on the account page', () {
    late List<Map<String, Object?>?> sent;

    setUp(() => sent = []);

    Future<void> approving(
      WidgetTester tester, {
      List<String> stages = const ['m.oauth'],
      Object? url = approvalUrl,
      int refusals = 0,
    }) => answering(
      tester,
      request: (auth) async {
        sent.add(auth?.toJson());
        if (sent.length <= refusals + 1) {
          throw uiaApprovalChallenge(stages: stages, url: url);
        }
      },
    );

    Future<void> tapButton(WidgetTester tester, Finder button) async {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    final cancelButton = find.widgetWithText(TextButton, 'Cancel');

    testWidgets('m.oauth opens the approval URL and continues with the '
        'session', (tester) async {
      await approving(tester);

      expect(opened, [approvalUrl]);
      expect(find.text('Approve in your browser'), findsOneWidget);
      expect(
        find.text(
          'example.org asks you to approve this on its account page. '
          'Approve it there, then come back and tap Continue.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not approved yet.'), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await tapButton(tester, continueButton);
      await outcome;

      expect(sent, [
        null,
        {'session': 'dummy'},
      ]);
      expect(failure, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('org.matrix.cross_signing_reset is handled the same', (
      tester,
    ) async {
      await approving(tester, stages: ['org.matrix.cross_signing_reset']);

      expect(opened, [approvalUrl]);
      await tapButton(tester, continueButton);
      await outcome;

      expect(sent, [
        null,
        {'session': 'dummy'},
      ]);
      expect(failure, isNull);
    });

    testWidgets('a second round says not approved yet and opens the page '
        'again', (tester) async {
      await approving(tester, refusals: 1);

      await tapButton(tester, continueButton);

      expect(find.text('Not approved yet.'), findsOneWidget);
      expect(find.text('Approve in your browser'), findsOneWidget);
      expect(opened, [approvalUrl, approvalUrl]);

      await tapButton(tester, continueButton);
      await outcome;

      expect(sent, [
        null,
        {'session': 'dummy'},
        {'session': 'dummy'},
      ]);
      expect(failure, isNull);
    });

    testWidgets('cancel cancels the request', (tester) async {
      await approving(tester);

      await tapButton(tester, cancelButton);
      await outcome;

      expect(sent, [null]);
      expect(isUiaCancel(failure!), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancel after a round not approved still cancels', (
      tester,
    ) async {
      await approving(tester, refusals: 1);
      await tapButton(tester, continueButton);

      await tapButton(tester, cancelButton);
      await outcome;

      expect(sent, [
        null,
        {'session': 'dummy'},
      ]);
      expect(isUiaCancel(failure!), isTrue);
    });

    for (final (label, url) in <(String, Object?)>[
      ('no link', null),
      ('a link that is not https', 'intent://account.example.org#Intent;end'),
    ]) {
      testWidgets('$label ends the request as a failure and opens '
          'nothing', (tester) async {
        await approving(tester, url: url);
        await outcome;

        expect(opened, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        expect(failure, isA<UnanswerableUiaStages>());
      });
    }

    testWidgets('password stages are unchanged when an approval is also '
        'offered', (tester) async {
      await answering(
        tester,
        request: (auth) async {
          if (auth == null) {
            throw MatrixException.fromJson({
              'session': 's1',
              'flows': [
                {
                  'stages': ['m.login.password'],
                },
                {
                  'stages': ['m.oauth'],
                },
              ],
              'params': {
                'm.oauth': {'url': approvalUrl},
              },
            });
          }
          tried.add((auth as AuthenticationPassword).password);
        },
      );

      expect(find.text('Confirm your password'), findsOneWidget);
      expect(opened, isEmpty);

      await enter(tester, 'right');
      await outcome;

      expect(tried, ['right']);
      expect(failure, isNull);
    });
  });
}
