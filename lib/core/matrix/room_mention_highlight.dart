import 'package:flutter/material.dart';

import 'matrix_ids.dart';

final _roomMention = RegExp(r'(?<![\w@])@room(?![\w])', caseSensitive: false);
final _tag = RegExp('<[^>]+>');
final _userPill = RegExp(
  r'<a\s[^>]*href="https://matrix\.to/#/@[^"]*"[^>]*>(.*?)</a>',
  caseSensitive: false,
  dotAll: true,
);

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

String _span(String hex, String text) =>
    '<span style="color: $hex; font-weight: bold;">$text</span>';

String highlightUserMentionsInHtml(String html, Color color) {
  final hex = _hex(color);
  return html.replaceAllMapped(
    _userPill,
    (m) => _span(hex, withoutServer(m.group(1)!)),
  );
}

String highlightRoomMentionsInHtml(String html, Color color) {
  final hex = _hex(color);
  String wrap(String segment) =>
      segment.replaceAllMapped(_roomMention, (m) => _span(hex, m.group(0)!));

  final buffer = StringBuffer();
  var last = 0;
  for (final tagMatch in _tag.allMatches(html)) {
    buffer
      ..write(wrap(html.substring(last, tagMatch.start)))
      ..write(tagMatch.group(0));
    last = tagMatch.end;
  }
  buffer.write(wrap(html.substring(last)));
  return buffer.toString();
}
