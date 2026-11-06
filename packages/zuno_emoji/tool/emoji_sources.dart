import 'package:zuno_emoji/src/emoji_entry.dart';

class Annotation {
  final String? name;
  final List<String> keywords;

  const Annotation({required this.name, required this.keywords});
}

const _groups = {
  'Smileys & Emotion': EmojiCategory.smileysPeople,
  'People & Body': EmojiCategory.smileysPeople,
  'Animals & Nature': EmojiCategory.animalsNature,
  'Food & Drink': EmojiCategory.foodDrink,
  'Travel & Places': EmojiCategory.travelPlaces,
  'Activities': EmojiCategory.activities,
  'Objects': EmojiCategory.objects,
  'Symbols': EmojiCategory.symbols,
  'Flags': EmojiCategory.flags,
};

const _firstTone = 0x1F3FB;
const _lastTone = 0x1F3FF;
const _presentationSelector = 0xFE0F;

final _line = RegExp(
  r'^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E(\d+)\.(\d+)\s',
);

List<EmojiEntry> parseEmojiTest(String text) {
  final result = <EmojiEntry>[];
  EmojiCategory? category;
  _Base? base;

  void closeBase() {
    final open = base;
    if (open == null) return;
    result.add(open.build());
    base = null;
  }

  for (final line in text.split('\n')) {
    if (line.startsWith('# group: ')) {
      closeBase();
      category = _groups[line.substring('# group: '.length).trim()];
      continue;
    }
    final match = _line.firstMatch(line);
    if (match == null || category == null) continue;
    final codes = match
        .group(1)!
        .split(' ')
        .map((h) => int.parse(h, radix: 16))
        .toList();
    final tones = codes
        .where((c) => c >= _firstTone && c <= _lastTone)
        .map((c) => c - _firstTone)
        .toList();
    final emoji = String.fromCharCodes(codes);
    if (tones.isEmpty) {
      closeBase();
      base = _Base(
        emoji: emoji,
        category: category,
        version: int.parse(match.group(2)!) * 10 + int.parse(match.group(3)!),
      );
      continue;
    }
    final open = base;
    if (open == null) {
      throw FormatException('Toned emoji with no base before it', line);
    }
    open.add(tones, emoji, line);
  }
  closeBase();
  return result;
}

class _Base {
  final String emoji;
  final EmojiCategory category;
  final int version;
  final _single = <int, String>{};
  final _pairs = <int, String>{};

  _Base({required this.emoji, required this.category, required this.version});

  void add(List<int> tones, String variant, String line) {
    switch (tones) {
      case [final t]:
        _single[t] = variant;
      case [final a, final b]:
        _pairs[EmojiEntry.pairIndex(a, b)] = variant;
      default:
        throw FormatException('More than two skin tones', line);
    }
  }

  EmojiEntry build() {
    if (_single.isEmpty && _pairs.isEmpty) {
      return EmojiEntry(emoji, category, version);
    }
    if (_pairs.isEmpty) {
      if (_single.length != skinToneCount) {
        throw FormatException('Expected $skinToneCount skin tones', emoji);
      }
      return EmojiEntry(emoji, category, version, ToneKind.one, [
        for (var t = 0; t < skinToneCount; t++) _single[t]!,
      ]);
    }
    final grid = <String>[];
    for (var a = 0; a < skinToneCount; a++) {
      for (var b = 0; b < skinToneCount; b++) {
        final variant =
            _pairs[EmojiEntry.pairIndex(a, b)] ?? (a == b ? _single[a] : null);
        if (variant == null) {
          throw FormatException('Missing skin tone pair $a,$b', emoji);
        }
        grid.add(variant);
      }
    }
    return EmojiEntry(emoji, category, version, ToneKind.two, grid);
  }
}

String lookupKey(String emoji) =>
    String.fromCharCodes(emoji.runes.where((r) => r != _presentationSelector));

final _annotation = RegExp(
  r'<annotation cp="([^"]+)"([^>]*)>([^<]*)</annotation>',
);
final _skippedDraft = RegExp(r'draft="(provisional|unconfirmed)"');

const _inherited = '↑↑↑';

Map<String, Annotation> parseAnnotations(String xml) {
  final names = <String, String?>{};
  final keywords = <String, List<String>>{};
  for (final match in _annotation.allMatches(xml)) {
    final attributes = match.group(2)!;
    if (_skippedDraft.hasMatch(attributes)) continue;
    final cp = lookupKey(_decode(match.group(1)!));
    final value = _decode(match.group(3)!).trim();
    if (attributes.contains('type="tts"')) {
      names[cp] = value == _inherited ? null : value;
    } else {
      keywords[cp] = value == _inherited
          ? const []
          : value
                .split('|')
                .map((k) => k.trim())
                .where((k) => k.isNotEmpty)
                .toList();
    }
  }
  return {
    for (final cp in {...names.keys, ...keywords.keys})
      cp: Annotation(name: names[cp], keywords: keywords[cp] ?? const []),
  };
}

Map<String, Annotation> mergeAnnotations(
  Map<String, Annotation> primary,
  Map<String, Annotation> derived,
) => {
  for (final cp in {...primary.keys, ...derived.keys})
    cp: Annotation(
      name: primary[cp]?.name ?? derived[cp]?.name,
      keywords: (primary[cp]?.keywords.isNotEmpty ?? false)
          ? primary[cp]!.keywords
          : derived[cp]?.keywords ?? const [],
    ),
};

String _decode(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

const _undecomposed = {
  'ł': 'l',
  'ø': 'o',
  'đ': 'd',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'ı': 'i',
  'ς': 'σ',
};

Map<String, String> foldMap(String unicodeData) {
  final decomposition = <int, int>{};
  for (final line in unicodeData.split('\n')) {
    final fields = line.split(';');
    if (fields.length < 6 || fields[5].isEmpty || fields[5].startsWith('<')) {
      continue;
    }
    decomposition[int.parse(fields[0], radix: 16)] = int.parse(
      fields[5].split(' ').first,
      radix: 16,
    );
  }
  int base(int code) {
    var current = code;
    for (var next = decomposition[current]; next != null;) {
      current = next;
      next = decomposition[current];
    }
    return current;
  }

  return {
    for (final code in decomposition.keys)
      if (base(code) != code)
        String.fromCharCode(code): String.fromCharCode(base(code)),
    ..._undecomposed,
  };
}

const _regionalIndicatorA = 0x1F1E6;
const _blackFlag = 0x1F3F4;
const _tagBase = 0xE0000;
const _cancelTag = 0xE007F;

String? flagRegion(String emoji) {
  final runes = emoji.runes.toList();
  if (runes.length == 2 &&
      runes.every(
        (r) => r >= _regionalIndicatorA && r < _regionalIndicatorA + 26,
      )) {
    return String.fromCharCodes(
      runes.map((r) => r - _regionalIndicatorA + 0x41),
    );
  }
  if (runes.length > 2 &&
      runes.first == _blackFlag &&
      runes.last == _cancelTag) {
    return String.fromCharCodes(
      runes.sublist(1, runes.length - 1).map((r) => r - _tagBase),
    );
  }
  return null;
}

final _regionName = RegExp(
  r'<(?:territory|subdivision) type="([A-Za-z0-9]+)">([^<]*)</(?:territory|subdivision)>',
);

Map<String, String> parseRegionNames(String xml) => {
  for (final match in _regionName.allMatches(xml))
    if (_decode(match.group(2)!).trim() case final name when name != _inherited)
      match.group(1)!: name,
};

Map<String, Annotation> fillFlagNames(
  Map<String, Annotation> annotations,
  Iterable<String> flags,
  Map<String, String> regionNames,
) => {
  ...annotations,
  for (final flag in flags)
    if (annotations[lookupKey(flag)]?.name == null)
      if (regionNames[flagRegion(flag)] case final name?)
        lookupKey(flag): Annotation(name: name, keywords: [name]),
};
