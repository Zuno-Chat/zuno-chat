import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/settings/presentation/chats_calls_settings_page.dart';

import '../../../helpers/card_layout.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/switch_tiles.dart';

void main() {
  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await containerWithPreferences(
      prefs,
      overrides: [
        matrixClientProvider.overrideWithValue(
          buildTestClient(userId: '@alice:example.org'),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatsCallsSettingsPage(),
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
    expect(switchedOn(tester, 'Prevent accidental calls'), isFalse);
  });

  testWidgets('a stored typing preference is read back as off', (tester) async {
    final container = await pumpPage(tester);
    await container.read(sendTypingIndicatorProvider.notifier).set(false);
    await tester.pump();

    expect(switchedOn(tester, 'Show when you are typing'), isFalse);
  });

  testWidgets('Matrix experience is off by default, shows what it '
      'changes with your own username, and turns on', (tester) async {
    final container = await pumpPage(tester);

    expect(container.read(matrixExperienceProvider), isFalse);
    expect(
      find.text(
        'Shows usernames and room addresses in full, like @alice:example.org',
      ),
      findsOneWidget,
    );
    await tester.tap(switchTile('Matrix experience'));
    await tester.pump();

    expect(container.read(matrixExperienceProvider), isTrue);
    expect(switchedOn(tester, 'Matrix experience'), isTrue);
  });

  testWidgets('a stored Matrix experience choice is read back as on', (
    tester,
  ) async {
    await pumpPage(tester, prefs: {'settings.matrix_experience': true});

    expect(switchedOn(tester, 'Matrix experience'), isTrue);
  });

  testWidgets('Matrix experience carries the Matrix logo, drawn like the '
      'other setting icons', (tester) async {
    await pumpPage(tester);

    final logo = tester.widget<SvgPicture>(
      find.descendant(
        of: switchTile('Matrix experience'),
        matching: find.byType(SvgPicture),
      ),
    );
    final iconTheme = IconTheme.of(
      tester.element(find.byIcon(Icons.more_horiz_outlined)),
    );
    expect(
      (logo.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/matrix.svg',
    );
    expect(
      logo.colorFilter,
      ColorFilter.mode(iconTheme.color!, BlendMode.srcIn),
    );
    expect(logo.width, iconTheme.size);
    expect(logo.height, iconTheme.size);
  });
}
