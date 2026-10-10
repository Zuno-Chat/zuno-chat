import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/security/prepared_uia_password.dart';
import 'package:zuno/features/settings/presentation/uia_password_prompt.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/uia_challenge.dart';

void main() {
  late Client client;
  late List<String> tried;
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
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    final sub = client.onUiaRequest.stream.listen(
      (uia) => answerUiaWithPassword(
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

  testWidgets('a next step that is not a password is cancelled, not called '
      'a wrong password', (tester) async {
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
    expect(failure.toString(), contains('canceled'));
  });
}
