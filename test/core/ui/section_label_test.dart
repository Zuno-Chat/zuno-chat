import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/section_label.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

void main() {
  testWidgets('shows its text small and muted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: const Scaffold(body: SectionLabel('Invitations')),
      ),
    );

    final text = tester.widget<Text>(find.text('Invitations'));
    expect(text.style!.fontSize, 12);
    expect(text.style!.fontWeight, FontWeight.w500);
    expect(text.style!.color, zunoLightTheme.colorScheme.onSurfaceVariant);
  });
}
