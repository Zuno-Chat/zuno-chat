import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/chats_calls_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/preferences_container.dart';

void main() {
  Finder switchTile(String title) =>
      find.widgetWithText(SwitchListTile, title, skipOffstage: false);

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await containerWithPreferences(prefs);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatsCallsSettingsPage()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('picking Dark changes the theme', (tester) async {
    final container = await pumpPage(tester);

    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('Prevent accidental calls is on by default, and turns off', (
    tester,
  ) async {
    final container = await pumpPage(tester);

    expect(container.read(confirmBeforeCallingProvider), isTrue);
    await tester.tap(switchTile('Prevent accidental calls'));
    await tester.pump();

    expect(container.read(confirmBeforeCallingProvider), isFalse);
    expect(
      tester
          .widget<SwitchListTile>(switchTile('Prevent accidental calls'))
          .value,
      isFalse,
    );
  });

  testWidgets('a stored typing preference is read back as off', (tester) async {
    final container = await pumpPage(tester);
    await container.read(sendTypingIndicatorProvider.notifier).set(false);
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(switchTile('Show when you are typing'))
          .value,
      isFalse,
    );
  });
}
