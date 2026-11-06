enum EmojiCategory {
  smileysPeople,
  animalsNature,
  foodDrink,
  travelPlaces,
  activities,
  objects,
  symbols,
  flags,
}

enum ToneKind { none, one, two }

const skinToneCount = 5;

class EmojiEntry {
  final String emoji;
  final EmojiCategory category;
  final int version;
  final ToneKind tones;
  final List<String> variants;

  const EmojiEntry(
    this.emoji,
    this.category,
    this.version, [
    this.tones = ToneKind.none,
    this.variants = const [],
  ]);

  static int pairIndex(int first, int second) => first * skinToneCount + second;

  (int, int) tonesOf(int variant) => tones == ToneKind.two
      ? (variant ~/ skinToneCount, variant % skinToneCount)
      : (variant, variant);
}
