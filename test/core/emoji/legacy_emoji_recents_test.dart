import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/emoji/emoji_catalog_provider.dart';
import 'package:zuno/core/emoji/legacy_emoji_recents.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

String _legacy(List<String> emoji) => jsonEncode([
  for (final e in emoji)
    {
      'emoji': {'emoji': e, 'name': 'x', 'hasSkinTone': false},
      'counter': 1,
    },
]);

void main() {
  Future<SharedPreferences> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test(
    'moves the old recent emoji over in their order and drops the old keys',
    () async {
      final preferences = await prefs({
        legacyEmojiRecentsKey: _legacy(['❤️', '👋🏽', '😀']),
        legacyEmojiSkinToneKey: '🏽',
      });
      await importLegacyEmojiRecents(preferences);
      expect(EmojiRecents(PreferencesEmojiStore(preferences)).items, [
        '❤️',
        '👋🏽',
        '😀',
      ]);
      expect(preferences.containsKey(legacyEmojiRecentsKey), isFalse);
      expect(preferences.containsKey(legacyEmojiSkinToneKey), isFalse);
    },
  );

  test('a corrupt old list is dropped without importing anything', () async {
    final preferences = await prefs({legacyEmojiRecentsKey: 'not json'});
    await importLegacyEmojiRecents(preferences);
    expect(EmojiRecents(PreferencesEmojiStore(preferences)).items, isEmpty);
    expect(preferences.containsKey(legacyEmojiRecentsKey), isFalse);
  });

  test('does nothing when there is nothing to import', () async {
    final preferences = await prefs({'emoji.recents': '["😀"]'});
    await importLegacyEmojiRecents(preferences);
    expect(preferences.getKeys(), {'emoji.recents'});
  });
}
