import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/src/data/emoji_table.g.dart';
import 'package:zuno_emoji/src/emoji_recents.dart';

import 'helpers.dart';

void main() {
  late MemoryEmojiStore store;

  setUp(() => store = MemoryEmojiStore());

  test('most recent first, without duplicates', () async {
    final recents = EmojiRecents(store);
    await recents.add('😀');
    await recents.add('❤️');
    await recents.add('😀');
    expect(recents.items, ['😀', '❤️']);
  });

  test('keeps at most 32', () async {
    final recents = EmojiRecents(store);
    for (final e in emojiTable.take(40)) {
      await recents.add(e.emoji);
    }
    expect(recents.items, hasLength(32));
    expect(recents.items.first, emojiTable[39].emoji);
  });

  test('a toned emoji replaces the same emoji in another tone', () async {
    final recents = EmojiRecents(store);
    await recents.add('👋');
    await recents.add('😀');
    await recents.add('👋🏽');
    expect(recents.items, ['👋🏽', '😀']);
  });

  test('survives a restart', () async {
    await EmojiRecents(store).add('😀');
    expect(EmojiRecents(store).items, ['😀']);
  });

  test('ignores a corrupt or unknown stored list', () {
    store.values['emoji.recents'] = '{"x":1}';
    expect(EmojiRecents(store).items, isEmpty);
    store.values['emoji.recents'] = '["😀","not an emoji"]';
    expect(EmojiRecents(store).items, ['😀']);
  });

  test('remembers the last tone per emoji, two people included', () async {
    final recents = EmojiRecents(store);
    final wave = emojiTable[indexOf('👋')];
    final kiss = emojiTable[indexOf('💏')];
    expect(recents.toneOf(wave), '👋');
    await recents.add('👋🏾');
    await recents.add(kiss.variants[1]);
    expect(recents.toneOf(wave), '👋🏾');
    expect(EmojiRecents(store).toneOf(kiss), kiss.variants[1]);
  });

  test('picking the untoned emoji forgets the tone', () async {
    final recents = EmojiRecents(store);
    final wave = emojiTable[indexOf('👋')];
    await recents.add('👋🏾');
    await recents.add('👋');
    expect(recents.toneOf(wave), '👋');
  });

  test('notifies listeners on add', () async {
    final recents = EmojiRecents(store);
    var calls = 0;
    recents.addListener(() => calls++);
    await recents.add('😀');
    expect(calls, 1);
  });

  test('forgets everything when the store is wiped underneath', () async {
    final recents = EmojiRecents(store);
    await recents.add('👋🏽');
    store.values.clear();
    expect(recents.items, isEmpty);
    expect(recents.toneOf(emojiTable[indexOf('👋')]), '👋');
    await recents.add('😀');
    expect(store.values['emoji.recents'], '["😀"]');
  });

  test('an emoji the table does not know is not remembered', () async {
    final recents = EmojiRecents(store);
    await recents.add('not an emoji');
    expect(recents.items, isEmpty);
    expect(store.writes, 0);
  });
}
