import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';

import 'data/emoji_table.g.dart';
import 'fold.dart';

String emojiLanguageFor(Locale locale) {
  final regional = locale.toString();
  if (emojiLanguages.contains(regional)) return regional;
  if (emojiLanguages.contains(locale.languageCode)) return locale.languageCode;
  return 'en';
}

typedef EmojiBackground = Future<T> Function<T>(T Function() work);

class EmojiNames {
  final List<String?> toneNames;
  final List<String?> _names;
  final List<List<String>> _keywords;
  final List<String?> _foldedNames;
  final List<List<String>> _nameWords;

  EmojiNames._(
    this.toneNames,
    this._names,
    this._keywords,
    this._foldedNames,
    this._nameWords,
  );

  factory EmojiNames.fromJson(String json) {
    final data = jsonDecode(json) as Map<String, Object?>;
    final entries = (data['names'] as List).cast<List<Object?>>();
    final names = [for (final e in entries) e[0] as String?];
    final folded = [
      for (final name in names) name == null ? null : foldText(name),
    ];
    return EmojiNames._(
      (data['tones'] as List).cast<String?>(),
      names,
      [
        for (final e in entries)
          [
            for (final k in (e[1] as String).split('|'))
              if (k.isNotEmpty) k,
          ],
      ],
      folded,
      [for (final name in folded) name?.split(' ') ?? const []],
    );
  }

  static Future<EmojiNames> load(
    String language, {
    EmojiBackground? background,
  }) async {
    final json = await rootBundle.loadString(
      'packages/zuno_emoji/assets/names/$language.json',
      cache: false,
    );
    return background == null
        ? EmojiNames.fromJson(json)
        : background(() => EmojiNames.fromJson(json));
  }

  String? name(int index) => index < _names.length ? _names[index] : null;

  int? score(int index, String foldedQuery) {
    if (index >= _names.length) return null;
    final name = _foldedNames[index];
    final keywords = _keywords[index];
    if (name == foldedQuery || keywords.contains(foldedQuery)) return 0;
    if (keywords.any((k) => k.startsWith(foldedQuery))) return 1;
    if (_nameWords[index].any((w) => w.startsWith(foldedQuery))) return 2;
    if ((name?.contains(foldedQuery) ?? false) ||
        keywords.any((k) => k.contains(foldedQuery))) {
      return 3;
    }
    return null;
  }
}
