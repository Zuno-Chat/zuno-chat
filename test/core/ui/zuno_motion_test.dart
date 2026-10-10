import 'dart:async';
import 'dart:math' as math;

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

  group('a forward-exit page', () {
    Route<void> forwardExitPage() => ForwardExitPageRoute(
      builder: (_) => const Scaffold(body: Text('second')),
    );

    Route<void> thirdPage() => MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('third')),
    );

    Future<void> leave(WidgetTester tester) async {
      ForwardExitPageRoute.popForward(tester.element(find.text('second')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    double widestGap(WidgetTester tester, List<String> pages) {
      final width = tester.getSize(find.byType(MaterialApp)).width;
      final lefts = [
        for (final page in pages)
          if (find.text(page).evaluate().isNotEmpty)
            tester.getTopLeft(find.text(page)).dx,
      ]..sort();
      var covered = 0.0;
      var widest = 0.0;
      for (final left in lefts) {
        widest = math.max(widest, left - covered);
        covered = math.max(covered, left + width);
      }
      return math.max(widest, width - covered);
    }

    final bothPlatforms = TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    });

    testWidgets('a plain pop goes back the usual way', (tester) async {
      await pumpApp(tester);
      push(tester, forwardExitPage());
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.text('second'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.getTopLeft(find.text('second')).dx, greaterThan(0));
    }, variant: bothPlatforms);

    testWidgets('with a page above it still leaving, it goes back the usual '
        'way and leaves no gap', (tester) async {
      await pumpApp(tester);
      push(tester, forwardExitPage());
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(tester.element(find.text('second'))).push(thirdPage()),
      );
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.text('third'))).pop();
      await tester.pump();
      ForwardExitPageRoute.popForward(tester.element(find.text('second')));
      var widest = 0.0;
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        widest = math.max(
          widest,
          widestGap(tester, ['first', 'second', 'third']),
        );
      }

      expect(widest, lessThan(2));
    }, variant: bothPlatforms);

    testWidgets('with another page on top, it leaves without taking that page '
        'with it', (tester) async {
      await pumpApp(tester);
      push(tester, forwardExitPage());
      await tester.pumpAndSettle();
      final leaving = tester.element(find.text('second'));
      unawaited(Navigator.of(leaving).push(thirdPage()));
      await tester.pumpAndSettle();

      ForwardExitPageRoute.popForward(leaving);
      await tester.pumpAndSettle();

      expect(find.text('third'), findsOneWidget);
      expect(find.text('second', skipOffstage: false), findsNothing);
    });

    testWidgets('slides forward over a page that returns a value', (
      tester,
    ) async {
      await pumpApp(tester);
      push(
        tester,
        MaterialPageRoute<bool>(
          builder: (_) => const Scaffold(body: Text('middle')),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(tester.element(find.text('middle')))
            .push(forwardExitPage()),
      );
      await tester.pumpAndSettle();

      await leave(tester);

      final width = tester.getSize(find.byType(MaterialApp)).width;
      final leaving = tester.getTopLeft(find.text('second')).dx;
      final arriving = tester.getTopLeft(find.text('middle')).dx;
      expect(leaving, lessThan(0));
      expect(arriving - leaving, closeTo(width, 1));
    }, variant: bothPlatforms);

    testWidgets('comes in like any other page', (tester) async {
      await pumpApp(tester);
      push(tester, forwardExitPage());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(tester.getTopLeft(find.text('second')).dx, greaterThan(0));
      expect(
        tester.getTopLeft(find.text('first', skipOffstage: false)).dx,
        lessThan(0),
      );
    }, variant: bothPlatforms);

    testWidgets('leaves forward: out to the left, with the page below coming '
        'in from the right', (tester) async {
      await pumpApp(tester);
      push(tester, forwardExitPage());
      await tester.pumpAndSettle();

      await leave(tester);

      final width = tester.getSize(find.byType(MaterialApp)).width;
      final leaving = tester.getTopLeft(find.text('second')).dx;
      final arriving = tester.getTopLeft(find.text('first')).dx;
      expect(leaving, lessThan(0));
      expect(arriving, greaterThan(0));
      expect(arriving - leaving, closeTo(width, 1));
    }, variant: bothPlatforms);

    testWidgets('takes as long as a step of the onboarding pager', (
      tester,
    ) async {
      await pumpApp(tester);
      push(tester, forwardExitPage());
      await tester.pumpAndSettle();

      await leave(tester);
      await tester.pump(
        ZunoDurations.standard - const Duration(milliseconds: 90),
      );
      await tester.pump();

      expect(find.text('second'), findsNothing);
      expect(tester.getTopLeft(find.text('first')).dx, 0);
    }, variant: bothPlatforms);

    testWidgets('with animations removed, it simply goes', (tester) async {
      await pumpApp(tester, disableAnimations: true);
      push(tester, forwardExitPage());
      await tester.pumpAndSettle();

      await leave(tester);

      expect(tester.getTopLeft(find.text('second')).dx, 0);

      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
    });
  });
}
