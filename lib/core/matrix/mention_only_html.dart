final _replyFallback = RegExp(
  r'<mx-reply>.*?</mx-reply>',
  caseSensitive: false,
  dotAll: true,
);
final _pill = RegExp(
  r'<a\s[^>]*href="https://matrix\.to/#/@[^"]*"[^>]*>(.*?)</a>',
  caseSensitive: false,
  dotAll: true,
);
final _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final _paragraph = RegExp(r'^<p>(.*)</p>$', dotAll: true);
final _anyTag = RegExp('<[^>]+>');

bool isMentionOnlyHtml({required String html, required String body}) {
  var text = html
      .replaceAll(_replyFallback, '')
      .trim()
      .replaceAllMapped(_pill, (m) => m.group(1)!);
  final wrapped = _paragraph.firstMatch(text);
  if (wrapped != null) text = wrapped.group(1)!;
  text = text.replaceAll(_lineBreak, '\n');
  if (_anyTag.hasMatch(text)) return false;
  return _unescape(text).trim() == body.trim();
}

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&amp;', '&');
