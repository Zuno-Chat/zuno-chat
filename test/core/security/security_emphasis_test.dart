import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/security_emphasis.dart';

void main() {
  group('securityStatusIcon', () {
    test('attention is a filled glyph, not the app-wide outlined default', () {
      expect(securityStatusIcon(attention: true), attentionIcon);
      expect(attentionIcon, isNot(Icons.warning_amber_outlined));
    });

    test('settled stays the muted outlined check', () {
      expect(securityStatusIcon(attention: false), settledIcon);
      expect(settledIcon, Icons.check_circle_outline);
    });
  });

  testWidgets('the stripe paints undiluted error colour', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: SizedBox(height: 40, child: AttentionStripe()),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    expect(container.color, scheme.error);
    expect(
      tester.getSize(find.byType(AttentionStripe)).width,
      attentionStripeWidth,
    );
  });

  Future<BuildContext> contextWith(WidgetTester tester, ThemeData theme) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('an approved device is a darker green on a light theme', (
    tester,
  ) async {
    final context = await contextWith(tester, ThemeData.light());

    expect(deviceApprovedColor(context), const Color(0xFF2E7D32));
  });

  testWidgets('an approved device is a lighter green on a dark theme', (
    tester,
  ) async {
    final context = await contextWith(tester, ThemeData.dark());

    expect(deviceApprovedColor(context), const Color(0xFF81C784));
  });

  testWidgets('an unapproved device takes the theme error colour', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final context = await contextWith(tester, ThemeData(colorScheme: scheme));

    expect(deviceUnapprovedColor(context), scheme.error);
  });
}
