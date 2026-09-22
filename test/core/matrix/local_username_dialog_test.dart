import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/local_username_dialog.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  String? userId;
  var closed = false;

  Future<void> openDialog(WidgetTester tester) async {
    userId = null;
    closed = false;
    final client = buildTestClient(userId: '@alice:zuno.chat')
      ..homeserver = Uri.parse('https://matrix.example.org');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              userId = await showLocalUsernameDialog(
                context,
                client: client,
                title: 'Invite someone',
                actionLabel: 'Invite',
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('builds the user ID on the server name, not the API host', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'bob');
    await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    await tester.pumpAndSettle();

    expect(userId, '@bob:zuno.chat');
  });

  testWidgets('a leading sigil in the field is not doubled up', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), '@bob');
    await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    await tester.pumpAndSettle();

    expect(userId, '@bob:zuno.chat');
  });

  testWidgets('the field holds to the sign-up character set', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'Bob-Smith_1');
    await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    await tester.pumpAndSettle();

    expect(userId, '@bobsmith_1:zuno.chat');
  });

  testWidgets('cancelling yields nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(userId, isNull);
  });

  testWidgets('an empty username yields nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Invite'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(userId, isNull);
  });
}
