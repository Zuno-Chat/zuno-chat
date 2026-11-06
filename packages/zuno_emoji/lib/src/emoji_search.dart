import 'data/emoji_table.g.dart';
import 'emoji_names.dart';
import 'fold.dart';

class EmojiSearch {
  final List<EmojiNames> _languages;
  final bool Function(int index) _include;
  var _lastQuery = '';
  var _lastHits = const <int>[];

  EmojiSearch(this._languages, {bool Function(int index)? include})
    : _include = include ?? _everything;

  static bool _everything(int index) => true;

  List<int> find(String query) {
    final folded = foldText(query.trim());
    if (folded.isEmpty) return const [];
    if (folded == _lastQuery) return _lastHits;
    final candidates = _lastQuery.isNotEmpty && folded.startsWith(_lastQuery)
        ? _lastHits
        : [
            for (var i = 0; i < emojiTable.length; i++)
              if (_include(i)) i,
          ];
    final scored = <(int, int)>[];
    for (final i in candidates) {
      int? best;
      for (final names in _languages) {
        final score = names.score(i, folded);
        if (score != null && (best == null || score < best)) best = score;
      }
      if (best != null) scored.add((best, i));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    _lastQuery = folded;
    return _lastHits = [for (final (_, i) in scored) i];
  }
}
