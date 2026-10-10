import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/settings/presentation/settings_widgets.dart';

import '../../../helpers/zuno_app.dart';

void main() {
  testWidgets(
    'ComingSoonTile shows title, subtitle, and a "Coming soon" chip',
    (tester) async {
      await tester.pumpWidget(
        inZunoApp(
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
}
