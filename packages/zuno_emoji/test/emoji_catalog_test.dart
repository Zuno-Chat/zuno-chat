import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/src/data/emoji_table.g.dart';
import 'package:zuno_emoji/src/emoji_catalog.dart';
import 'package:zuno_emoji/src/emoji_entry.dart';
import 'package:zuno_emoji/src/emoji_names.dart';
import 'package:zuno_emoji/src/emoji_recents.dart';

import 'helpers.dart';

void main() {
  late EmojiRecents recents;

  EmojiCatalog catalog({
    Set<String> undrawable = const {},
    String language = 'de',
  }) => EmojiCatalog(
    names: realNames(language),
    english: realNames('en'),
    recents: recents,
    undrawable: undrawable,
  );

  setUp(() => recents = EmojiRecents(MemoryEmojiStore()));

  test(
    'lists each category in Unicode order, leaving out undrawable emoji',
    () {
      final smileys = catalog(undrawable: {'😃'})
          .category(EmojiCategory.smileysPeople);
      expect(smileys.take(3).map((e) => e.emoji), ['😀', '😄', '😁']);
      expect(
        catalog()
            .category(EmojiCategory.flags)
            .every((e) => e.category == EmojiCategory.flags),
        isTrue,
      );
    },
  );

  test('offers tones only when every variant is drawable', () {
    final wave = emojiTable[indexOf('👋')];
    expect(catalog().showsTones(wave), isTrue);
    expect(catalog(undrawable: {'👋🏿'}).showsTones(wave), isFalse);
    expect(catalog().showsTones(emojiTable[indexOf('😀')]), isFalse);
  });

  test('shows the remembered tone in the grid', () async {
    final wave = emojiTable[indexOf('👋')];
    await recents.add('👋🏽');
    expect(catalog().shown(wave), '👋🏽');
    expect(catalog(undrawable: {'👋🏿'}).shown(wave), '👋');
  });

  test('labels emoji in the app language, tones included', () {
    final kiss = emojiTable[indexOf('💏')];
    expect(catalog().label('😀'), 'grinsendes Gesicht');
    expect(catalog().label('👋🏻'), 'winkende Hand: helle Hautfarbe');
    expect(
      catalog().label(kiss.variants[0]),
      'sich küssendes Paar: helle Hautfarbe',
    );
    expect(
      catalog().label(kiss.variants[4]),
      'sich küssendes Paar: helle Hautfarbe, dunkle Hautfarbe',
    );
  });

  test('labels fall back to English when the language lacks a name', () {
    expect(catalog(language: 'da').label('#️⃣'), 'keycap: #');
  });

  test('recent emoji leave out what is no longer drawable', () async {
    await recents.add('😀');
    await recents.add('🫫');
    expect(catalog(undrawable: {'🫫'}).recent, ['😀']);
  });

  test('search returns drawable entries in rank order', () {
    final results = catalog(undrawable: {'💓'}).search('herz');
    expect(results.map((e) => e.emoji), contains('❤️'));
    expect(results.map((e) => e.emoji), isNot(contains('💓')));
  });

  test('the app language picks its own names, regional ones included', () {
    expect(emojiLanguageFor(const Locale('pt', 'PT')), 'pt_PT');
    expect(emojiLanguageFor(const Locale('pt', 'BR')), 'pt');
    expect(emojiLanguageFor(const Locale('de', 'AT')), 'de');
    expect(emojiLanguageFor(const Locale('nb')), 'nb');
    expect(emojiLanguageFor(const Locale('ja')), 'en');
  });
}
