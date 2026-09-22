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
}
