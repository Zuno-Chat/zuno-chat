import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/empty_state.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

void main() {
  testWidgets('shows the icon, the title and the body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: const Scaffold(
          body: EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No chats yet',
            body: 'Tap + to start one.',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    final title = tester.widget<Text>(find.text('No chats yet'));
    expect(title.style!.fontSize, 20);
    expect(title.style!.fontWeight, FontWeight.w500);
    final body = tester.widget<Text>(find.text('Tap + to start one.'));
    expect(body.style!.color, zunoLightTheme.colorScheme.onSurfaceVariant);
    expect(find.byType(Opacity), findsNothing);
  });
}
