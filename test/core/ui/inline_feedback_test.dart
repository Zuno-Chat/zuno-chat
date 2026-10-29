import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/inline_feedback.dart';

void main() {
  testWidgets('an inline error is red and announced when it appears', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: const Scaffold(body: InlineError('Wrong password'))),
    );
    final context = tester.element(find.text('Wrong password'));

    expect(
      tester.widget<Text>(find.text('Wrong password')).style?.color,
      Theme.of(context).colorScheme.error,
    );
    expect(
      tester.getSemantics(find.text('Wrong password')),
      matchesSemantics(label: 'Wrong password', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('an icon-slot spinner fills the icon box', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: InlineSpinner.icon())),
    );
    expect(tester.getSize(find.byType(InlineSpinner)), const Size(24, 24));
    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(20, 20),
    );
  });
}
