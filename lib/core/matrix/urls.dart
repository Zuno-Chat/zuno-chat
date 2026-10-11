final _linkCandidate = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

const _sentencePunctuation = '.,;:!?\'"';

const _openerOf = {')': '(', ']': '[', '}': '{'};

Iterable<({int start, int end, Uri uri})> linksIn(String text) sync* {
  for (final match in _linkCandidate.allMatches(text)) {
    final link = match.group(0)!;
    final length = _lengthWithoutStrayPunctuation(link);
    final uri = Uri.tryParse(link.substring(0, length));
    if (uri == null || !isSafeExternalUri(uri)) continue;
    yield (start: match.start, end: match.start + length, uri: uri);
  }
}

int _lengthWithoutStrayPunctuation(String link) {
  final counts = <String, int>{};
  for (var i = 0; i < link.length; i++) {
    counts.update(link[i], (n) => n + 1, ifAbsent: () => 1);
  }
  var length = link.length;
  while (length > 0) {
    final last = link[length - 1];
    if (!_sentencePunctuation.contains(last)) {
      final opener = _openerOf[last];
      if (opener == null || counts[last]! <= (counts[opener] ?? 0)) break;
      counts[last] = counts[last]! - 1;
    }
    length--;
  }
  return length;
}

const _safeExternalSchemes = {'https', 'http', 'mailto'};

bool isSafeExternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (!_safeExternalSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return uri.path.isNotEmpty;
  return uri.hasAuthority && uri.host.isNotEmpty;
}
