import 'data/emoji_table.g.dart';

class EmojiRef {
  final int index;
  final int? variant;

  const EmojiRef(this.index, this.variant);
}

final Map<String, EmojiRef> emojiIndex = {
  for (var i = 0; i < emojiTable.length; i++) ...{
    emojiTable[i].emoji: EmojiRef(i, null),
    for (var v = 0; v < emojiTable[i].variants.length; v++)
      emojiTable[i].variants[v]: EmojiRef(i, v),
  },
};
