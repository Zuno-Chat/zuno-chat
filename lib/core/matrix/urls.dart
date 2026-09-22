final urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

Uri? firstLinkIn(String text) {
  final match = urlPattern.firstMatch(text);
  if (match == null) return null;
  return Uri.tryParse(match.group(0)!);
}

const _safeExternalSchemes = {'https', 'http', 'mailto'};

bool isSafeExternalUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (!_safeExternalSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return uri.path.isNotEmpty;
  return uri.hasAuthority && uri.host.isNotEmpty;
}
