import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/settings/presentation/settings_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SettingsSectionHeader shows its title', (tester) async {
    await tester.pumpWidget(
      _wrap(const SettingsSectionHeader('Notifications')),
    );
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets(
    'ComingSoonTile shows title, subtitle, and a "Coming soon" chip',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ComingSoonTile(
            icon: Icons.call,
            title: 'Group calls',
            subtitle: 'Soon!',
          ),
        ),
      );
      expect(find.text('Group calls'), findsOneWidget);
      expect(find.text('Soon!'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.enabled, isFalse);
    },
  );

  testWidgets('ComingSoonTile with no subtitle omits the subtitle line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ComingSoonTile(icon: Icons.call, title: 'Group calls')),
    );
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.subtitle, isNull);
  });

  testWidgets('ComingSoonSwitchTile is off and cannot be toggled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ComingSoonSwitchTile(icon: Icons.lock, title: 'Key backup')),
    );
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNull);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
