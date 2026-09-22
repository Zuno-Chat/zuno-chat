import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/blocking/presentation/blocked_people_page.dart';
import 'package:zuno/features/settings/presentation/advanced_security_page.dart';
import 'package:zuno/features/settings/presentation/security_privacy_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const callsChannel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(callsChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(callsChannel, null));

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
    final client = buildTestClient(userId: '@me:example.org');
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: SecurityPrivacySettingsPage());
          },
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('every setting sits on a card', (tester) async {
    await pumpPage(tester);

    expectEveryRowOnACard();
  });

  testWidgets('Blocked people opens the list of blocked people', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Blocked people'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockedPeoplePage), findsOneWidget);
    expect(find.text('Nobody is blocked'), findsOneWidget);
  });

  testWidgets('App lock no longer appears anywhere on the page', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('App lock'), findsNothing);
  });

  testWidgets('Prevent screenshots is a real, enabled toggle — on by default', (
    tester,
  ) async {
    await pumpPage(tester);

    final tile = tester.widget<SwitchListTile>(
      switchTile('Prevent screenshots'),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);
    expect(
      tile.subtitle,
      isNot(isA<Text>().having((t) => t.data, 'data', 'Coming soon')),
    );
  });

  testWidgets('reads a previously-stored false value as off', (tester) async {
    await pumpPage(tester, prefs: {'settings.prevent_screenshots': false});

    final tile = tester.widget<SwitchListTile>(
      switchTile('Prevent screenshots'),
    );
    expect(tile.value, isFalse);
  });

  testWidgets('tapping the toggle flips it, persists it, and calls the native '
      'FLAG_SECURE channel', (tester) async {
    final container = await pumpPage(tester);

    await tester.tap(switchTile('Prevent screenshots'));
    await tester.pump();

    expect(container.read(preventScreenshotsProvider), isFalse);
    final tile = tester.widget<SwitchListTile>(
      switchTile('Prevent screenshots'),
    );
    expect(tile.value, isFalse);

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool('settings.prevent_screenshots'), isFalse);

    expect(
      calls,
      contains(
        isA<MethodCall>()
            .having((c) => c.method, 'method', 'setPreventScreenshots')
            .having((c) => c.arguments, 'arguments', {'enabled': false}),
      ),
    );
  });

  testWidgets(
    'tapping it while off turns it back on and calls the channel with true',
    (tester) async {
      final container = await pumpPage(
        tester,
        prefs: {'settings.prevent_screenshots': false},
      );

      await tester.tap(switchTile('Prevent screenshots'));
      await tester.pump();

      expect(container.read(preventScreenshotsProvider), isTrue);
      expect(
        calls,
        contains(
          isA<MethodCall>()
              .having((c) => c.method, 'method', 'setPreventScreenshots')
              .having((c) => c.arguments, 'arguments', {'enabled': true}),
        ),
      );
    },
  );

  testWidgets(
    "the row's subtitle discloses the recent-apps-thumbnail side effect",
    (tester) async {
      await pumpPage(tester);
      expect(
        find.textContaining('recent apps preview', skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('Incognito keyboard is a real toggle — on by default', (
    tester,
  ) async {
    final container = await pumpPage(tester);
    final tile = tester.widget<SwitchListTile>(
      switchTile('Incognito keyboard'),
    );
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNotNull);

    await tester.tap(switchTile('Incognito keyboard'));
    await tester.pump();

    expect(container.read(incognitoKeyboardProvider), isFalse);
  });

  testWidgets('Send crash reports moved out, to About', (tester) async {
    await pumpPage(tester);

    expect(find.text('Send crash reports', skipOffstage: false), findsNothing);
  });

  testWidgets('Advanced is a disabled placeholder that opens nothing', (
    tester,
  ) async {
    await pumpPage(tester);

    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Advanced', skipOffstage: false),
    );
    expect(row.enabled, isFalse);

    await tester.tap(find.text('Advanced'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(AdvancedSecurityPage), findsNothing);
  });
}
