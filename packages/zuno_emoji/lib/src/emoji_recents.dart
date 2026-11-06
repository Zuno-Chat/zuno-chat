import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/emoji_table.g.dart';
import 'emoji_entry.dart';
import 'emoji_index.dart';
import 'emoji_store.dart';
import 'json.dart';

const _recentsKey = 'emoji.recents';
const _tonesKey = 'emoji.tones';
const _limit = 32;

class EmojiRecents extends ChangeNotifier {
  final EmojiStore _store;
  final _items = _Parsed<List<String>>(_readList);
  final _tones = _Parsed<Map<String, String>>(_readTones);

  EmojiRecents(this._store);

  List<String> get items => List.unmodifiable(_currentItems());

  String toneOf(EmojiEntry entry) =>
      _currentTones()[entry.emoji] ?? entry.emoji;

  Future<void> add(String emoji) => addAll([emoji]);

  Future<void> addAll(Iterable<String> oldestFirst) async {
    final items = [..._currentItems()];
    final tones = {..._currentTones()};
    var tonesChanged = false;
    for (final emoji in oldestFirst) {
      final ref = emojiIndex[emoji];
      if (ref == null) continue;
      items
        ..removeWhere((e) => emojiIndex[e]?.index == ref.index)
        ..insert(0, emoji);
      final entry = emojiTable[ref.index];
      if (entry.tones == ToneKind.none) continue;
      tonesChanged = true;
      if (ref.variant == null) {
        tones.remove(entry.emoji);
      } else {
        tones[entry.emoji] = emoji;
      }
    }
    final kept = items.take(_limit).toList();
    final rawItems = _items.remember(jsonEncode(kept), kept);
    final rawTones = tonesChanged
        ? _tones.remember(jsonEncode(tones), tones)
        : null;
    notifyListeners();
    await _store.write(_recentsKey, rawItems);
    if (rawTones != null) await _store.write(_tonesKey, rawTones);
  }

  List<String> _currentItems() => _items.of(_store.read(_recentsKey));

  Map<String, String> _currentTones() => _tones.of(_store.read(_tonesKey));

  static List<String> _readList(String? raw) => switch (decodeJsonOrNull(raw)) {
    final List list => [
      for (final e in list)
        if (e is String && emojiIndex.containsKey(e)) e,
    ],
    _ => [],
  };

  static Map<String, String> _readTones(String? raw) =>
      switch (decodeJsonOrNull(raw)) {
        final Map map => {
          for (final MapEntry(:key, :value) in map.entries)
            if (key is String &&
                value is String &&
                emojiIndex.containsKey(value))
              key: value,
        },
        _ => {},
      };
}

class _Parsed<T> {
  final T Function(String? raw) _parse;
  String? _raw;
  T? _value;

  _Parsed(this._parse);

  T of(String? raw) {
    final value = _value;
    if (value != null && raw == _raw) return value;
    _raw = raw;
    return _value = _parse(raw);
  }

  String remember(String raw, T value) {
    _raw = raw;
    _value = value;
    return raw;
  }
}
