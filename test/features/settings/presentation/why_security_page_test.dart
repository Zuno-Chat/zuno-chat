import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/navigation/zuno_links.dart';
import 'package:zuno/features/settings/presentation/why_security_page.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    double height = 640,
    double bottomInset = 0,
    WhySecurityPage page = const WhySecurityPage(),
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
  }

  testWidgets('answers each question under its own heading', (tester) async {
    await pumpPage(tester, height: 3000);

    expect(find.text('How this works'), findsOneWidget);
    for (final heading in [
      'Why a recovery code',
      'Why new devices ask for approval',
      'Why confirming people matters',
      'Confirmed people only',
      'When Zuno interrupts you',
    ]) {
      expect(
        find.text(heading, skipOffstage: false),
        findsOneWidget,
        reason: heading,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('names the limits of encryption up front', (tester) async {
    await pumpPage(tester);

    expect(
      find.textContaining('does not hide who you talk to'),
      findsOneWidget,
    );
  });

  testWidgets('the last row clears the system navigation bar', (tester) async {
    await pumpPage(tester, bottomInset: 48);

    for (var i = 0; i < 5; i++) {
      await tester.fling(find.byType(ListView), const Offset(0, -600), 3000);
      await tester.pumpAndSettle();
    }

    final last = tester.getRect(find.byType(ListTile));
    expect(last.bottom, lessThanOrEqualTo(640 - 48));
  });

  testWidgets('the last row opens every protection on the website', (
    tester,
  ) async {
    final opened = <Uri>[];
    await pumpPage(
      tester,
      height: 3000,
      page: WhySecurityPage(
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    await tester.tap(find.text("All of Zuno's protections"));
    await tester.pump();

    expect(opened, [securityUri]);
    expect(find.text('zuno.chat/security'), findsOneWidget);
  });

  testWidgets('says where to go when no browser opens the link', (
    tester,
  ) async {
    await pumpPage(
      tester,
      height: 3000,
      page: WhySecurityPage(openUrl: (_) async => false),
    );

    await tester.tap(find.text("All of Zuno's protections"));
    await tester.pump();

    expect(
      find.text('Link not opened. Visit zuno.chat/security in a browser.'),
      findsOneWidget,
    );
  });
}
