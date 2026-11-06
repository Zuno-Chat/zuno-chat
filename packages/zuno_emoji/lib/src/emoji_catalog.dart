import 'dart:ui';

import 'data/emoji_table.g.dart';
import 'emoji_entry.dart';
import 'emoji_index.dart';
import 'emoji_names.dart';
import 'emoji_recents.dart';
import 'emoji_search.dart';
import 'emoji_support.dart';

class EmojiCatalog {
  final EmojiNames _names;
  final EmojiNames _english;
  final EmojiRecents recents;
  final Set<String> _undrawable;
  final bool provisional;
  late final _search = EmojiSearch([
    _names,
    if (!identical(_names, _english)) _english,
  ], include: (i) => _drawable(emojiTable[i].emoji));
  final _categories = <EmojiCategory, List<EmojiEntry>>{};

  EmojiCatalog({
    required this._names,
    required this._english,
    required this.recents,
    required this._undrawable,
    this.provisional = false,
  });

  static Future<EmojiCatalog> load({
    required Locale locale,
    required EmojiRecents recents,
    required EmojiSupport support,
    EmojiBackground? background,
  }) async {
    final language = emojiLanguageFor(locale);
    final undrawable = support.undrawable();
    final english = EmojiNames.load('en', background: background);
    final names = language == 'en'
        ? english
        : EmojiNames.load(language, background: background);
    return EmojiCatalog(
      names: await names,
      english: await english,
      recents: recents,
      undrawable: await undrawable,
      provisional: !support.settled,
    );
  }

  bool _drawable(String emoji) => !_undrawable.contains(emoji);

  List<EmojiEntry> category(EmojiCategory category) =>
      _categories[category] ??= [
        for (final e in emojiTable)
          if (e.category == category && _drawable(e.emoji)) e,
      ];

  bool showsTones(EmojiEntry entry) =>
      entry.tones != ToneKind.none && entry.variants.every(_drawable);

  String shown(EmojiEntry entry) =>
      showsTones(entry) ? recents.toneOf(entry) : entry.emoji;

  List<String> get recent => [
    for (final e in recents.items)
      if (_drawable(e)) e,
  ];

  List<EmojiEntry> search(String query) => [
    for (final i in _search.find(query)) emojiTable[i],
  ];

  EmojiEntry? entryOf(String emoji) => switch (emojiIndex[emoji]) {
    final ref? => emojiTable[ref.index],
    null => null,
  };

  String label(String emoji) {
    final ref = emojiIndex[emoji];
    if (ref == null) return emoji;
    final base = _names.name(ref.index) ?? _english.name(ref.index) ?? emoji;
    final variant = ref.variant;
    if (variant == null) return base;
    final (first, second) = emojiTable[ref.index].tonesOf(variant);
    final tones = first == second
        ? _tone(first)
        : '${_tone(first)}, ${_tone(second)}';
    return '$base: $tones';
  }

  String _tone(int tone) => _names.toneNames[tone] ?? _english.toneNames[tone]!;
}
