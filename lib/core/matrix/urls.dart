final _linkCandidate = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

const _sentencePunctuation = '.,;:!?\'"';

const _openerOf = {')': '(', ']': '[', '}': '{'};

Iterable<({int start, int end, Uri uri})> linksIn(String text) sync* {
  for (final match in _linkCandidate.allMatches(text)) {
    var link = match.group(0)!;
    while (link.isNotEmpty && _endsInStrayPunctuation(link)) {
      link = link.substring(0, link.length - 1);
    }
    final uri = Uri.tryParse(link);
    if (uri == null || !isSafeExternalUri(uri)) continue;
    yield (start: match.start, end: match.start + link.length, uri: uri);
  }
}

bool _endsInStrayPunctuation(String link) {
  final last = link[link.length - 1];
  if (_sentencePunctuation.contains(last)) return true;
  final opener = _openerOf[last];
  if (opener == null) return false;
  return last.allMatches(link).length > opener.allMatches(link).length;
}

const _safeExternalSchemes = {'https', 'http', 'mailto'};

bool isSafeExternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (!_safeExternalSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return uri.path.isNotEmpty;
  return uri.hasAuthority && uri.host.isNotEmpty;
}
