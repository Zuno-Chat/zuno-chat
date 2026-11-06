import 'dart:convert';
import 'dart:io';

import 'package:zuno_emoji/src/data/emoji_table.g.dart';
import 'package:zuno_emoji/src/emoji_index.dart';
import 'package:zuno_emoji/src/emoji_names.dart';
import 'package:zuno_emoji/src/emoji_store.dart';
import 'package:zuno_emoji/src/fold.dart';

EmojiNames realNames(String language) =>
    EmojiNames.fromJson(File('assets/names/$language.json').readAsStringSync());

EmojiNames namesWith(Map<String, (String, List<String>)> entries) {
  final names = List<Object?>.filled(emojiTable.length, [null, '']);
  for (final MapEntry(key: emoji, value: (name, keywords)) in entries.entries) {
    names[indexOf(emoji)] = [name, keywords.map(foldText).join('|')];
  }
  return EmojiNames.fromJson(
    jsonEncode({
      'tones': ['t1', 't2', 't3', 't4', 't5'],
      'names': names,
    }),
  );
}

int indexOf(String emoji) => emojiIndex[emoji]!.index;

class MemoryEmojiStore implements EmojiStore {
  final values = <String, String>{};
  var writes = 0;
  var failWrites = false;

  @override
  String? read(String key) => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    writes++;
    values[key] = value;
  }
}
