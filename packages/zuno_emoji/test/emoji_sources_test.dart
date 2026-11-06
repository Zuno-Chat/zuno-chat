import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/src/emoji_entry.dart';

import '../tool/emoji_sources.dart';

final _emojiTest =
    '''
# group: Smileys & Emotion

# subgroup: face-smiling
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
263A FE0F                                              ; fully-qualified     # ☺️ E0.6 smiling face
263A                                                   ; unqualified         # ☺ E0.6 smiling face

# group: People & Body

# subgroup: hand-fingers-open
1F44B                                                  ; fully-qualified     # 👋 E0.6 waving hand
1F44B 1F3FB                                            ; fully-qualified     # 👋🏻 E1.0 waving hand: light skin tone
1F44B 1F3FC                                            ; fully-qualified     # 👋🏼 E1.0 waving hand: medium-light skin tone
1F44B 1F3FD                                            ; fully-qualified     # 👋🏽 E1.0 waving hand: medium skin tone
1F44B 1F3FE                                            ; fully-qualified     # 👋🏾 E1.0 waving hand: medium-dark skin tone
1F44B 1F3FF                                            ; fully-qualified     # 👋🏿 E1.0 waving hand: dark skin tone
1F3CC FE0F 200D 2642 FE0F                              ; fully-qualified     # 🏌️‍♂️ E4.0 man golfing
1F3CC 200D 2642 FE0F                                   ; unqualified         # 🏌‍♂️ E4.0 man golfing
1F3CC 1F3FB 200D 2642 FE0F                             ; fully-qualified     # 🏌🏻‍♂️ E4.0 man golfing: light skin tone
1F3CC 1F3FC 200D 2642 FE0F                             ; fully-qualified     # 🏌🏼‍♂️ E4.0 man golfing: medium-light skin tone
1F3CC 1F3FD 200D 2642 FE0F                             ; fully-qualified     # 🏌🏽‍♂️ E4.0 man golfing: medium skin tone
1F3CC 1F3FE 200D 2642 FE0F                             ; fully-qualified     # 🏌🏾‍♂️ E4.0 man golfing: medium-dark skin tone
1F3CC 1F3FF 200D 2642 FE0F                             ; fully-qualified     # 🏌🏿‍♂️ E4.0 man golfing: dark skin tone
${_twoTone()}
# group: Component

# subgroup: skin-tone
1F3FB                                                  ; component           # 🏻 E1.0 light skin tone

# group: Flags

# subgroup: country-flag
1F1E9 1F1EA                                            ; fully-qualified     # 🇩🇪 E2.0 flag: Germany

# subgroup: new
1FAEB                                                  ; fully-qualified     # 🫫 E18.0 cracking face
''';

const _tones = ['1F3FB', '1F3FC', '1F3FD', '1F3FE', '1F3FF'];

String _twoTone() {
  final lines = [
    '1F48F                                                  ; fully-qualified     # 💏 E0.6 kiss',
  ];
  for (final t in _tones) {
    lines.add('1F48F $t ; fully-qualified # x E13.1 kiss: tone');
  }
  for (final a in _tones) {
    for (final b in _tones) {
      if (a == b) continue;
      lines.add(
        '1F9D1 $a 200D 2764 FE0F 200D 1F48B 200D 1F9D1 $b ; fully-qualified # x E13.1 kiss: person, person, tones',
      );
    }
  }
  return lines.join('\n');
}

String _seq(String hex) =>
    String.fromCharCodes(hex.split(' ').map((h) => int.parse(h, radix: 16)));

void main() {
  group('parseEmojiTest', () {
    final parsed = parseEmojiTest(_emojiTest);
    EmojiEntry find(String emoji) =>
        parsed.singleWhere((e) => e.emoji == emoji);

    test('keeps fully-qualified emoji in order and drops components', () {
      expect(parsed.map((e) => e.emoji), [
        '😀',
        '☺️',
        '👋',
        _seq('1F3CC FE0F 200D 2642 FE0F'),
        '💏',
        '🇩🇪',
        '🫫',
      ]);
    });

    test('maps Unicode groups to categories', () {
      expect(find('😀').category, EmojiCategory.smileysPeople);
      expect(find('👋').category, EmojiCategory.smileysPeople);
      expect(find('🇩🇪').category, EmojiCategory.flags);
    });

    test('reads the emoji version', () {
      expect(find('☺️').version, 6);
      expect(find('🫫').version, 180);
    });

    test('collects one-tone variants', () {
      final wave = find('👋');
      expect(wave.tones, ToneKind.one);
      expect(wave.variants, ['👋🏻', '👋🏼', '👋🏽', '👋🏾', '👋🏿']);
      expect(
        find(_seq('1F3CC FE0F 200D 2642 FE0F')).variants.first,
        _seq('1F3CC 1F3FB 200D 2642 FE0F'),
      );
    });

    test(
      'fills a 5x5 grid for two-person emoji, same tones on the diagonal',
      () {
        final kiss = find('💏');
        expect(kiss.tones, ToneKind.two);
        expect(kiss.variants, hasLength(25));
        expect(kiss.variants[0], _seq('1F48F 1F3FB'));
        expect(kiss.variants[6], _seq('1F48F 1F3FC'));
        expect(
          kiss.variants[1],
          _seq('1F9D1 1F3FB 200D 2764 FE0F 200D 1F48B 200D 1F9D1 1F3FC'),
        );
        expect(
          kiss.variants[23],
          _seq('1F9D1 1F3FF 200D 2764 FE0F 200D 1F48B 200D 1F9D1 1F3FE'),
        );
      },
    );

    test('emoji without tones have no variants', () {
      expect(find('😀').tones, ToneKind.none);
      expect(find('😀').variants, isEmpty);
    });

    test('a toned emoji with no base before it is an error', () {
      expect(
        () => parseEmojiTest(
          '# group: People & Body\n1F44B 1F3FB ; fully-qualified # 👋🏻 E1.0 x\n',
        ),
        throwsFormatException,
      );
    });

    test('an incomplete tone set is an error', () {
      expect(
        () => parseEmojiTest(
          '# group: People & Body\n'
          '1F44B ; fully-qualified # 👋 E0.6 x\n'
          '1F44B 1F3FB ; fully-qualified # 👋🏻 E1.0 x\n',
        ),
        throwsFormatException,
      );
    });
  });

  group('parseAnnotations', () {
    const xml = '''
<ldml>
	<annotations>
		<annotation cp="❤">Herz | Liebe</annotation>
		<annotation cp="❤" type="tts">rotes Herz</annotation>
		<annotation cp="😀">Gesicht | grinsend</annotation>
		<annotation cp="😀" type="tts">↑↑↑</annotation>
		<annotation cp="🫫">A &amp; B | &lt;tag&gt;</annotation>
		<annotation cp="😋" draft="contributed">lecker | Zunge</annotation>
		<annotation cp="😋" type="tts" draft="contributed">leckeres Gesicht</annotation>
		<annotation cp="🚌" draft="provisional">Bus</annotation>
		<annotation cp="🚌" type="tts" draft="unconfirmed">Bus</annotation>
	</annotations>
</ldml>
''';
    final annotations = parseAnnotations(xml);

    test('reads keywords and the spoken name', () {
      expect(annotations['❤']!.keywords, ['Herz', 'Liebe']);
      expect(annotations['❤']!.name, 'rotes Herz');
    });

    test('treats an inherited marker as missing', () {
      expect(annotations['😀']!.name, isNull);
      expect(annotations['😀']!.keywords, ['Gesicht', 'grinsend']);
    });

    test('decodes XML entities', () {
      expect(annotations['🫫']!.keywords, ['A & B', '<tag>']);
    });

    test('keeps contributed drafts and skips provisional and unconfirmed', () {
      expect(annotations['😋']!.keywords, ['lecker', 'Zunge']);
      expect(annotations['😋']!.name, 'leckeres Gesicht');
      expect(annotations.containsKey('🚌'), isFalse);
    });

    test('looks emoji up without the emoji presentation selector', () {
      expect(lookupKey('❤️'), '❤');
      expect(lookupKey('😀'), '😀');
    });

    test('derived annotations fill gaps but never override', () {
      final merged = mergeAnnotations(annotations, {
        '❤': const Annotation(name: 'Herz', keywords: ['x']),
        '😀': const Annotation(name: 'grinsendes Gesicht', keywords: []),
        '🇩🇪': const Annotation(
          name: 'Flagge: Deutschland',
          keywords: ['Flagge'],
        ),
      });
      expect(merged['❤']!.name, 'rotes Herz');
      expect(merged['❤']!.keywords, ['Herz', 'Liebe']);
      expect(merged['😀']!.name, 'grinsendes Gesicht');
      expect(merged['🇩🇪']!.name, 'Flagge: Deutschland');
    });
  });

  group('foldMap', () {
    const unicodeData = '''
0065;LATIN SMALL LETTER E;Ll;0;L;;;;;N;;;0045;;0045
00E9;LATIN SMALL LETTER E WITH ACUTE;Ll;0;L;0065 0301;;;;N;LATIN SMALL LETTER E ACUTE;;00C9;;00C9
1EC7;LATIN SMALL LETTER E WITH CIRCUMFLEX AND DOT BELOW;Ll;0;L;1EB9 0302;;;;N;;;1EC6;;1EC6
1EB9;LATIN SMALL LETTER E WITH DOT BELOW;Ll;0;L;0065 0323;;;;N;;;1EB8;;1EB8
03AC;GREEK SMALL LETTER ALPHA WITH TONOS;Ll;0;L;03B1 0301;;;;N;GREEK SMALL LETTER ALPHA TONOS;;0386;;0386
00BD;VULGAR FRACTION ONE HALF;No;0;ON;<fraction> 0031 2044 0032;;;1/2;N;FRACTION ONE HALF;;;;
''';
    final fold = foldMap(unicodeData);

    test('maps accented letters to their base letter', () {
      expect(fold['é'], 'e');
      expect(fold['ά'], 'α');
    });

    test('follows decompositions to the base letter', () {
      expect(fold['ệ'], 'e');
    });

    test('skips compatibility decompositions', () {
      expect(fold.containsKey('½'), isFalse);
    });

    test('adds letters Unicode does not decompose', () {
      expect(fold['ł'], 'l');
      expect(fold['ø'], 'o');
      expect(fold['ß'], 'ss');
      expect(fold['ς'], 'σ');
    });
  });

  group('flag names', () {
    test('a country flag names its region code', () {
      expect(flagRegion('🇩🇰'), 'DK');
    });

    test('a subdivision flag names its subdivision code', () {
      expect(
        flagRegion(_seq('1F3F4 E0067 E0062 E0065 E006E E0067 E007F')),
        'gbeng',
      );
    });

    test('other emoji have no region', () {
      expect(flagRegion('🏁'), isNull);
      expect(flagRegion('😀'), isNull);
    });

    test('reads region names, skipping alternates and inherited ones', () {
      const xml = '''
			<territory type="DK">Danmark</territory>
			<territory type="GB">Storbritannien</territory>
			<territory type="GB" alt="short">UK</territory>
			<territory type="HK">↑↑↑</territory>
			<subdivision type="gbeng">England</subdivision>
''';
      expect(parseRegionNames(xml), {
        'DK': 'Danmark',
        'GB': 'Storbritannien',
        'gbeng': 'England',
      });
    });

    test('fills a flag missing a name from the region name', () {
      final filled = fillFlagNames(
        {
          '🇩🇪': const Annotation(name: 'Flag: Tyskland', keywords: ['flag']),
        },
        ['🇩🇪', '🇩🇰', '🇿🇿'],
        {'DK': 'Danmark', 'DE': 'Tyskland'},
      );
      expect(filled['🇩🇪']!.name, 'Flag: Tyskland');
      expect(filled['🇩🇰']!.name, 'Danmark');
      expect(filled['🇩🇰']!.keywords, ['Danmark']);
      expect(filled.containsKey('🇿🇿'), isFalse);
    });
  });
}
