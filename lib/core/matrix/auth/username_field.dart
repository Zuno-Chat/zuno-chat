import 'package:flutter/services.dart';

import '../matrix_ids.dart';

final lowercaseFormatter = TextInputFormatter.withFunction(
  (_, value) => value.copyWith(text: value.text.toLowerCase()),
);

final usernameCharsFormatter = FilteringTextInputFormatter.allow(
  RegExp('[$matrixLocalpartChars]'),
);

TextInputFormatter ownServerIdFormatter(String server) {
  final ownId = RegExp(
    '^@?([^:]*):${RegExp.escape(server)}\$',
    caseSensitive: false,
  );
  return TextInputFormatter.withFunction((_, value) {
    final username = ownId.firstMatch(value.text.trim())?.group(1);
    if (username == null) return value;
    return TextEditingValue(
      text: username,
      selection: TextSelection.collapsed(offset: username.length),
    );
  });
}
