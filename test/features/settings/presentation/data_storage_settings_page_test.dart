import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/data_storage_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';

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
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        matrixClientProvider.overrideWithValue(
          buildTestClient(userId: '@me:example.org'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DataStorageSettingsPage()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('holds the data toggles and both cache actions', (tester) async {
    await pumpPage(tester);

    expect(find.text('Data & storage'), findsOneWidget);
    expect(switchTile('Reduce media size'), findsOneWidget);
    expect(switchTile('Use less data for calls'), findsOneWidget);
    expect(find.text('Clear cache'), findsOneWidget);
    expect(find.text('Clear media cache'), findsOneWidget);
  });

  testWidgets('both data toggles are on by default', (tester) async {
    await pumpPage(tester);

    expect(
      tester.widget<SwitchListTile>(switchTile('Reduce media size')).value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(switchTile('Use less data for calls'))
          .value,
      isTrue,
    );
    expect(find.text('Video is capped at 360p and 24 fps'), findsOneWidget);
  });

  testWidgets('Reduce media size turns off and persists', (tester) async {
    final container = await pumpPage(tester);

    await tester.tap(switchTile('Reduce media size'));
    await tester.pump();

    expect(container.read(reduceMediaSizeProvider), isFalse);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('settings.reduce_media_size'),
      isFalse,
    );
  });

  testWidgets('Use less data for calls turns off and says what it now caps', (
    tester,
  ) async {
    final container = await pumpPage(tester);

    await tester.tap(switchTile('Use less data for calls'));
    await tester.pump();

    expect(container.read(lowDataCallsProvider), isFalse);
    expect(find.textContaining('480p'), findsOneWidget);
  });

  testWidgets('stored off values are read back', (tester) async {
    await pumpPage(
      tester,
      prefs: {
        'settings.reduce_media_size': false,
        'settings.low_data_calls': false,
      },
    );

    expect(
      tester.widget<SwitchListTile>(switchTile('Reduce media size')).value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(switchTile('Use less data for calls'))
          .value,
      isFalse,
    );
  });

  testWidgets('Clear cache asks first, and Cancel clears nothing', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();
    expect(find.text('Clear cache?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Clear cache?'), findsNothing);
    expect(find.text('Cache cleared'), findsNothing);
  });
}
