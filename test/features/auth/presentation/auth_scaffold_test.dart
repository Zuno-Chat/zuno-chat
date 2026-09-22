import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/auth/presentation/auth_scaffold.dart';

void main() {
  Widget page() => AuthScaffold(
    title: 'Sign in',
    footer: [
      OutlinedButton(onPressed: () {}, child: const Text('Create account')),
    ],
    children: [
      const TextField(decoration: InputDecoration(labelText: 'Username')),
      const SizedBox(height: 16),
      const TextField(decoration: InputDecoration(labelText: 'Password')),
      const SizedBox(height: 24),
      FilledButton(onPressed: () {}, child: const Text('Go')),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    bool pushed = false,
    Size size = const Size(360, 640),
    double keyboard = 0,
    double navigationBar = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.view.padding = FakeViewPadding(bottom: navigationBar);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: pushed ? const Scaffold() : page(),
      ),
    );
    if (pushed) {
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute<void>(builder: (_) => page()));
      await tester.pumpAndSettle();
    }
  }

  Finder inCard(Finder finder) =>
      find.descendant(of: find.byKey(authCardKey), matching: finder);

  testWidgets('the mark and the name sit above a card that holds the form', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Zuno'), findsOneWidget);
    expect(inCard(find.text('Sign in')), findsOneWidget);
    expect(inCard(find.byType(TextField)), findsNWidgets(2));
    expect(inCard(find.widgetWithText(FilledButton, 'Go')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Zuno')).dy,
      lessThan(tester.getTopLeft(find.byKey(authCardKey)).dy),
    );
  });

  testWidgets('the footer sits under the card, not in it', (tester) async {
    await pump(tester);

    final footer = find.widgetWithText(OutlinedButton, 'Create account');
    expect(inCard(footer), findsNothing);
    expect(
      tester.getTopLeft(footer).dy,
      greaterThan(tester.getBottomLeft(find.byKey(authCardKey)).dy),
    );
  });

  testWidgets('a first screen has no back button, a pushed one does', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(BackButton), findsNothing);

    await pump(tester, pushed: true);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('with the keyboard open nothing overflows and the button can '
      'be reached', (tester) async {
    await pump(tester, keyboard: 300);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Go'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Go')).bottom,
      lessThanOrEqualTo(640 - 300),
    );
  });

  testWidgets('the footer clears the navigation bar', (tester) async {
    await pump(tester, size: const Size(360, 420), navigationBar: 48);

    final footer = find.widgetWithText(OutlinedButton, 'Create account');
    await tester.ensureVisible(footer);
    await tester.pump();
    expect(tester.getBottomLeft(footer).dy, lessThanOrEqualTo(420 - 48));
  });

  testWidgets('a screen with no title shows the card without one', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: const AuthScaffold(children: [Text('Cannot reach the server')]),
      ),
    );

    expect(inCard(find.text('Cannot reach the server')), findsOneWidget);
  });
}
