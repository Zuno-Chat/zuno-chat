import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/navigation/launch_route.dart';
import 'package:zuno/core/ui/zuno_motion.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, {bool disableAnimations = false}) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

  group('MediaViewerRoute', () {
    MediaViewerRoute viewer() =>
        MediaViewerRoute(builder: (_) => const Text('viewer'));

    testWidgets('fades in over the screen below, then covers it', (
      tester,
    ) async {
      await pumpApp(tester);
      push(tester, viewer());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('first'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('viewer'),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );

      await tester.pump(ZunoDurations.page);
      expect(find.text('viewer'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    });

    testWidgets('shows the screen below again while asked to', (tester) async {
      await pumpApp(tester);
      final route = viewer();
      push(tester, route);
      await tester.pump();
      await tester.pump(ZunoDurations.page * 2);
      expect(find.text('first'), findsNothing);

      route.revealRouteBelow(true);
      await tester.pump();
      expect(find.text('first'), findsOneWidget);

      route.revealRouteBelow(false);
      await tester.pump();
      expect(find.text('first'), findsNothing);
    });

    testWidgets('with animations removed, it appears without a fade or a '
        'flight', (tester) async {
      await pumpApp(tester, disableAnimations: true);
      push(tester, viewer());
      await tester.pump();
      await tester.pump(ZunoDurations.page * 2);

      expect(
        find.ancestor(
          of: find.text('viewer'),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<HeroMode>(
              find
                  .ancestor(
                    of: find.text('viewer'),
                    matching: find.byType(HeroMode),
                  )
                  .first,
            )
            .enabled,
        isFalse,
      );
    });
  });

  group('MediaHero', () {
    testWidgets('without a tag it is just its child', (tester) async {
      await tester.pumpWidget(const MediaHero(tag: null, child: SizedBox()));

      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('a kept-visible source still shows its child in flight', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaHero(tag: 't', keepsSourceVisible: true, child: SizedBox()),
      );

      final hero = tester.widget<Hero>(find.byType(Hero));
      expect(hero.placeholderBuilder, isNotNull);
      expect(hero.flightShuttleBuilder, isNotNull);
    });
  });
}
