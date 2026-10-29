import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/alert_banner.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);

  Future<void> pump(WidgetTester tester, Widget banner) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: scheme),
      home: Scaffold(body: banner),
    ),
  );

  testWidgets('the stripe paints undiluted error colour', (tester) async {
    await pump(tester, const SizedBox(height: 40, child: AttentionStripe()));

    final container = tester.widget<Container>(find.byType(Container));
    expect(container.color, scheme.error);
    expect(
      tester.getSize(find.byType(AttentionStripe)).width,
      attentionStripeWidth,
    );
  });

  testWidgets('shows the title, body, footnote and its one action', (
    tester,
  ) async {
    var acted = 0;
    await pump(
      tester,
      AlertBanner(
        icon: Icons.warning_rounded,
        title: 'Title',
        body: 'Body',
        footnote: 'Footnote',
        actionLabel: 'Act',
        onAction: () => acted++,
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Footnote'), findsOneWidget);
    expect(find.byType(AttentionStripe), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Act'));
    expect(acted, 1);
  });

  testWidgets('a dismissible banner closes with the ✕', (tester) async {
    var dismissed = 0;
    await pump(
      tester,
      AlertBanner(
        icon: Icons.warning_rounded,
        title: 'Title',
        onDismiss: () => dismissed++,
      ),
    );

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    expect(dismissed, 1);
  });

  testWidgets('a notice has no stripe and a calmer colour', (tester) async {
    await pump(
      tester,
      const AlertBanner(
        icon: Icons.info_outline,
        title: 'Title',
        tone: AlertBannerTone.notice,
      ),
    );

    expect(find.byType(AttentionStripe), findsNothing);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Title'), matching: find.byType(Material))
          .first,
    );
    expect(material.color, scheme.secondaryContainer);
  });

  group('the info strip', () {
    Color background(WidgetTester tester) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text('Title'), matching: find.byType(Material))
              .first,
        )
        .color!;

    testWidgets('sits on the notice colour with its action in line', (
      tester,
    ) async {
      var acted = 0;
      var tapped = 0;
      await pump(
        tester,
        InfoStrip(
          icon: Icons.call_outlined,
          title: 'Title',
          actionLabel: 'Join',
          onAction: () => acted++,
          onTap: () => tapped++,
        ),
      );

      expect(background(tester), scheme.secondaryContainer);
      expect(
        tester.getCenter(find.text('Join')).dy,
        moreOrLessEquals(tester.getCenter(find.text('Title')).dy, epsilon: 1),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      expect(acted, 1);
      expect(tapped, 0);

      await tester.tap(find.text('Title'));
      expect(tapped, 1);
    });

    testWidgets('a body goes under the title', (tester) async {
      await pump(
        tester,
        const InfoStrip(icon: Icons.schedule, title: 'Title', body: 'Body'),
      );

      expect(
        tester.getTopLeft(find.text('Body')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Title')).dy),
      );
    });

    testWidgets('without an action or a tap it is only words', (tester) async {
      await pump(tester, const InfoStrip(icon: Icons.schedule, title: 'Title'));

      expect(find.byType(FilledButton), findsNothing);
      expect(
        tester.getSemantics(find.text('Title')),
        isNot(matchesSemantics(isButton: true)),
      );
      expect(find.byType(AttentionStripe), findsNothing);
    });
  });
}
