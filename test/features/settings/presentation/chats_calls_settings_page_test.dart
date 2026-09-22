import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/chats_calls_settings_page.dart';

import '../../../helpers/card_layout.dart';

void main() {
  Finder switchTile(String title) =>
      find.widgetWithText(SwitchListTile, title, skipOffstage: false);

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sharedPrefs)],
    );
    addTearDown(container.dispose);
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

  testWidgets('holds the theme, the chat toggles and the call toggle', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Chats & calls'), findsOneWidget);
    expect(find.text('Follow system'), findsOneWidget);
    expect(switchTile('Show when you are typing'), findsOneWidget);
    expect(switchTile('Prevent accidental calls'), findsOneWidget);
  });

  testWidgets('no Link previews row, live or placeholder', (tester) async {
    await pumpPage(tester);

    expect(find.text('Link previews'), findsNothing);
  });

  testWidgets('data, storage and diagnostics rows live elsewhere', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Reduce media size'), findsNothing);
    expect(find.text('Use less data for calls'), findsNothing);
    expect(find.text('Show hidden messages'), findsNothing);
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

  testWidgets('a stored off for Prevent accidental calls is read back', (
    tester,
  ) async {
    await pumpPage(tester, prefs: {'settings.confirm_before_calling': false});

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
