import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/emoji/emoji_catalog_provider.dart';
import 'package:zuno/core/l10n/app_locale.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/l10n/app_localizations.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import '../../helpers/preferences_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every app language has its own emoji names', () {
    for (final locale in AppLocalizations.supportedLocales) {
      expect(emojiLanguageFor(locale), locale.toString(), reason: '$locale');
    }
  });

  group('emojiCatalogProvider', () {
    Future<ProviderContainer> container({
      Future<List<bool>> Function(List<String> emoji)? probe,
    }) => containerWithPreferences(
      {},
      overrides: [
        emojiSupportProvider.overrideWith(
          (ref) => EmojiSupport(
            store: ref.watch(emojiStoreProvider),
            environment: 'test',
            deadline: Duration.zero,
            probe: probe ?? (emoji) async => [for (final _ in emoji) true],
          ),
        ),
      ],
    );

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localeChannel, null),
    );

    test(
      'names emoji in the app language and follows a language change',
      () async {
        final emoji = await container();
        final english = await emoji.read(emojiCatalogProvider.future);
        expect(english.label('😀'), 'grinning face');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(localeChannel, (_) async => 'de');
        AppLocale.instance.didChangeLocales(null);
        await pumpEventQueue();

        final german = await emoji.read(emojiCatalogProvider.future);
        expect(german.label('😀'), 'grinsendes Gesicht');
        expect(german.recents, same(english.recents));
      },
    );

    test('a slow drawable check is swapped in once it lands', () async {
      final answer = Completer<List<bool>>();
      var probed = const <String>[];
      final emoji = await container(
        probe: (candidates) {
          probed = candidates;
          return answer.future;
        },
      );
      final sub = emoji.listen(emojiCatalogProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await emoji.read(emojiCatalogProvider.future);
      expect(first.provisional, isTrue);
      expect(first.showsTones(first.entryOf('👋')!), isFalse);

      answer.complete([for (final _ in probed) true]);
      await pumpEventQueue();

      final settled = await emoji.read(emojiCatalogProvider.future);
      expect(settled.provisional, isFalse);
      expect(settled.showsTones(settled.entryOf('👋')!), isTrue);
    });

    test('keeps recent emoji in the preferences', () async {
      final emoji = await container();
      await emoji.read(emojiRecentsProvider).add('😀');
      expect(
        emoji.read(sharedPreferencesProvider).getString('emoji.recents'),
        '["😀"]',
      );
    });
  });
}
