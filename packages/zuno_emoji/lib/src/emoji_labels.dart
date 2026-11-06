import 'emoji_entry.dart';

class EmojiLabels {
  final Map<EmojiCategory, String> categories;
  final String recent;
  final String search;
  final String noResults;
  final String noRecents;
  final String backspace;
  final String closeSearch;

  const EmojiLabels({
    required this.categories,
    required this.recent,
    required this.search,
    required this.noResults,
    required this.noRecents,
    required this.backspace,
    required this.closeSearch,
  });
}
