import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/navigation/launch_route.dart';
import 'package:zuno/core/ui/zuno_motion.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, {bool disableAnimations = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {TargetPlatform.android: ZunoSlideTransitionsBuilder()},
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: const Scaffold(body: Text('first')),
        ),
      );

  void push(WidgetTester tester, Route<void> route) {
    Navigator.of(tester.element(find.text('first'))).push(route);
  }

  Route<void> secondPage() => MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('second')),
  );

  testWidgets('a push slides the new screen in and shifts the old one left', (
    tester,
  ) async {
    await pumpApp(tester);
    push(tester, secondPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(tester.getTopLeft(find.text('second')).dx, greaterThan(0));
    expect(
      tester.getTopLeft(find.text('first', skipOffstage: false)).dx,
      lessThan(0),
    );

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('second')).dx, 0);
  });

  testWidgets('a third of the way in, most of the slide is still ahead', (
    tester,
  ) async {
    await pumpApp(tester);
    push(tester, secondPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final width = tester.getSize(find.byType(MaterialApp)).width;
    expect(tester.getTopLeft(find.text('second')).dx, greaterThan(width * 0.4));
  });

  testWidgets('the push never fades', (tester) async {
    await pumpApp(tester);
    push(tester, secondPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final fades = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.text('second'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades.every((fade) => fade.opacity.value == 1), isTrue);
    expect(
      find.ancestor(of: find.text('second'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('with animations removed, the new screen is simply there', (
    tester,
  ) async {
    await pumpApp(tester, disableAnimations: true);
    push(tester, secondPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(tester.getTopLeft(find.text('second')).dx, 0);
    expect(
      find.ancestor(
        of: find.text('second'),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('a launch route still opens instantly', (tester) async {
    await pumpApp(tester);
    push(
      tester,
      LaunchRoute<void>(builder: (_) => const Scaffold(body: Text('second'))),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(find.text('second')).dx, 0);
  });

  test('the push lasts as long as the page token', () {
    expect(
      const ZunoSlideTransitionsBuilder().transitionDuration,
      ZunoDurations.page,
    );
    expect(ZunoDurations.page, const Duration(milliseconds: 300));
    expect(ZunoDurations.standard, const Duration(milliseconds: 250));
    expect(ZunoDurations.fast, const Duration(milliseconds: 150));
  });
}
