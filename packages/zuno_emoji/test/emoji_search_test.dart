import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/src/emoji_search.dart';

import 'helpers.dart';

void main() {
  group('ranking', () {
    final search = EmojiSearch([
      namesWith({
        '😀': ('grinning face', ['face', 'grin']),
        '😁': ('beaming face', ['grinning', 'smile']),
        '😃': ('happy grin', ['joy']),
        '☕': ('hot beverage', ['café', 'drink']),
      }),
    ]);

    test(
      'an exact keyword beats a keyword prefix, which beats a name match',
      () {
        expect(search.find('grin'), [
          indexOf('😀'),
          indexOf('😁'),
          indexOf('😃'),
        ]);
      },
    );

    test('ignores case and accents in both directions', () {
      expect(search.find('CAFE'), [indexOf('☕')]);
      expect(search.find('café'), [indexOf('☕')]);
    });

    test('an empty or blank query finds nothing', () {
      expect(search.find(''), isEmpty);
      expect(search.find('   '), isEmpty);
    });

    test('leaves out what the caller excludes', () {
      final drawable = EmojiSearch([
        namesWith({
          '😀': ('grinning face', ['grin']),
          '😁': ('beaming face', ['grin']),
        }),
      ], include: (i) => i != indexOf('😁'));
      expect(drawable.find('grin'), [indexOf('😀')]);
    });

    test('typing on narrows the last results the same as a fresh search', () {
      final typing = EmojiSearch([realNames('en')]);
      for (final prefix in ['h', 'he', 'hea', 'hear', 'heart']) {
        typing.find(prefix);
      }
      expect(
        typing.find('heart'),
        EmojiSearch([realNames('en')]).find('heart'),
      );
      expect(typing.find('hea'), EmojiSearch([realNames('en')]).find('hea'));
    });

    test('takes the best match across languages', () {
      final both = EmojiSearch([
        namesWith({
          '😀': ('grinsendes Gesicht', ['Gesicht']),
        }),
        namesWith({
          '😀': ('grinning face', ['grin']),
          '😁': ('beaming face', ['grin']),
        }),
      ]);
      expect(both.find('grin'), [indexOf('😀'), indexOf('😁')]);
    });
  });

  group('real data', () {
    test('German finds the red heart', () {
      expect(
        EmojiSearch([realNames('de')]).find('herz'),
        contains(indexOf('❤️')),
      );
    });

    test('Greek matches without accents', () {
      expect(
        EmojiSearch([realNames('el')]).find('καρδια'),
        contains(indexOf('❤️')),
      );
    });

    test('English is searched as well as the app language', () {
      final search = EmojiSearch([realNames('de'), realNames('en')]);
      expect(search.find('grinning'), contains(indexOf('😀')));
    });

    test('a Danish flag is found by its Danish country name', () {
      expect(EmojiSearch([realNames('da')]).find('danmark'), [indexOf('🇩🇰')]);
    });
  });
}
