import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';

class MentionQuery {
  final int start;
  final String text;

  const MentionQuery({required this.start, required this.text});

  @override
  bool operator ==(Object other) =>
      other is MentionQuery && other.start == start && other.text == text;

  @override
  int get hashCode => Object.hash(start, text);

  @override
  String toString() => 'MentionQuery(start: $start, text: $text)';
}

final _whitespace = RegExp(r'\s');
final _localpartRun = RegExp(
  '^[$matrixLocalpartChars]*\$',
  caseSensitive: false,
);

MentionQuery? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && !_whitespace.hasMatch(before[at - 1])) return null;
  final query = before.substring(at + 1);
  if (!_localpartRun.hasMatch(query)) return null;
  return MentionQuery(start: at, text: query);
}

List<User> mentionMatches(List<User> members, String query, {int? limit}) {
  final needle = query.toLowerCase();
  String name(User user) => user.calcDisplayname().toLowerCase();
  bool matches(User user) =>
      needle.isEmpty ||
      name(user).contains(needle) ||
      (user.id.localpart ?? '').toLowerCase().contains(needle);

  final found = members.where(matches).toList()
    ..sort((a, b) => name(a).compareTo(name(b)));
  return limit == null ? found : found.take(limit).toList();
}

String mentionInsertText(User user) {
  final fragments = user.mentionFragments;
  return fragments.isEmpty
      ? '@${user.id.localpart ?? user.id}'
      : fragments.first;
}

({String text, int cursor}) applyMention(
  String text,
  MentionQuery query, {
  required int cursor,
  required String insert,
}) {
  final replacement = '$insert ';
  return (
    text: text.replaceRange(query.start, cursor, replacement),
    cursor: query.start + replacement.length,
  );
}
