class CleartextRefusedException implements Exception {
  const CleartextRefusedException(this.uri);

  final Uri uri;

  @override
  String toString() =>
      'CleartextRefusedException: refused ${uri.scheme}://${uri.host}';
}

CleartextRefusedException? cleartextRefusal(
  Uri uri, {
  required String secureScheme,
}) => uri.isScheme(secureScheme) ? null : CleartextRefusedException(uri);
