const _firstCombiningMark = 0x300;
const _lastCombiningMark = 0x36F;

String foldWith(Map<String, String> map, String text) {
  final out = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if (rune >= _firstCombiningMark && rune <= _lastCombiningMark) continue;
    final char = String.fromCharCode(rune);
    out.write(map[char] ?? char);
  }
  return out.toString();
}
