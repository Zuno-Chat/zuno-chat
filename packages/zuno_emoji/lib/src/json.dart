import 'dart:convert';

Object? decodeJsonOrNull(String? raw) {
  if (raw == null) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}
