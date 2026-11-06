import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import '../async/background_work.dart';
import '../errors/caught_errors.dart';
import '../l10n/app_locale.dart';
import '../platform/platform_capabilities.dart';
import '../settings/app_preferences_provider.dart';

class PreferencesEmojiStore implements EmojiStore {
  final SharedPreferences _preferences;

  PreferencesEmojiStore(this._preferences);

  @override
  String? read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

DrawableProbe _drawableProbe = probeDrawable;

@visibleForTesting
set drawableProbe(DrawableProbe probe) => _drawableProbe = probe;

Future<T> _inBackground<T>(T Function() work) =>
    runInBackground(work, debugName: 'emoji names');

final emojiStoreProvider = Provider<EmojiStore>(
  (ref) => PreferencesEmojiStore(ref.watch(sharedPreferencesProvider)),
);

final emojiRecentsProvider = Provider<EmojiRecents>((ref) {
  final recents = EmojiRecents(ref.watch(emojiStoreProvider));
  ref.onDispose(recents.dispose);
  return recents;
});

final emojiSupportProvider = Provider<EmojiSupport>((ref) {
  final support = EmojiSupport(
    store: ref.watch(emojiStoreProvider),
    probe: _drawableProbe,
    environment:
        '${ref.watch(operatingSystemVersionProvider)}|'
        '${FlutterVersion.engineRevision}',
    onError: (error, stack) =>
        reportCaught('emoji drawable check', error, stack),
  );
  ref.onDispose(support.dispose);
  return support;
});

final emojiLocaleProvider = Provider<Locale>((ref) {
  void changed() => ref.invalidateSelf();
  AppLocale.instance.addListener(changed);
  ref.onDispose(() => AppLocale.instance.removeListener(changed));
  return AppLocale.instance.value;
});

final emojiCatalogProvider = FutureProvider<EmojiCatalog>((ref) async {
  final support = ref.watch(emojiSupportProvider);
  try {
    final catalog = await EmojiCatalog.load(
      locale: ref.watch(emojiLocaleProvider),
      recents: ref.watch(emojiRecentsProvider),
      support: support,
      background: _inBackground,
    );
    if (catalog.provisional) {
      void settled() => ref.invalidateSelf();
      support.addListener(settled);
      ref.onDispose(() => support.removeListener(settled));
    }
    return catalog;
  } catch (error, stack) {
    reportCaught('load the emoji list', error, stack);
    rethrow;
  }
});
