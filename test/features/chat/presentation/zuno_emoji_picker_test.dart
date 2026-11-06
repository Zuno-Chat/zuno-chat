import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/emoji/emoji_catalog_provider.dart';
import 'package:zuno/features/chat/presentation/zuno_emoji_picker.dart';
import 'package:zuno/l10n/app_localizations.dart';

import '../../../helpers/fake_emoji.dart';
import '../../../helpers/preferences_container.dart';

void main() {
  late ProviderContainer container;
  late int loads;

  Future<void> show(WidgetTester tester, {required bool shown}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TickerMode(
              enabled: shown,
              child: ZunoEmojiPicker(onSelected: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open({required bool provisional}) async {
    loads = 0;
    container = await containerWithPreferences(
      {},
      overrides: [
        emojiCatalogProvider.overrideWith((ref) async {
          loads++;
          return fakeCatalog(
            ref.watch(emojiRecentsProvider),
            provisional: provisional,
          );
        }),
      ],
    );
  }

  testWidgets('a list built while the drawable check failed asks again when '
      'it shows again', (tester) async {
    await open(provisional: true);
    await show(tester, shown: true);
    expect(loads, 1);

    await show(tester, shown: false);
    await show(tester, shown: true);

    expect(loads, 2);
  });

  testWidgets('a settled list is not loaded again', (tester) async {
    await open(provisional: false);
    await show(tester, shown: true);
    await show(tester, shown: false);
    await show(tester, shown: true);

    expect(loads, 1);
  });
}
