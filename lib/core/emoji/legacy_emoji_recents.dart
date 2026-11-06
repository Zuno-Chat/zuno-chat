import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import 'emoji_catalog_provider.dart';

const legacyEmojiRecentsKey = 'recent';
const legacyEmojiSkinToneKey = 'skin_tone';

Future<void> importLegacyEmojiRecents(SharedPreferences preferences) async {
  final raw = preferences.getString(legacyEmojiRecentsKey);
  if (raw == null && !preferences.containsKey(legacyEmojiSkinToneKey)) return;
  final recents = EmojiRecents(PreferencesEmojiStore(preferences));
  await recents.addAll(_legacyEmoji(raw).reversed);
  recents.dispose();
  await preferences.remove(legacyEmojiRecentsKey);
  await preferences.remove(legacyEmojiSkinToneKey);
}

List<String> _legacyEmoji(String? raw) {
  if (raw == null) return const [];
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item case {'emoji': {'emoji': final String emoji}}) emoji,
    ];
  } on FormatException {
    return const [];
  }
}
