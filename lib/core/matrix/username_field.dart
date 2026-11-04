import 'package:flutter/services.dart';

import 'matrix_ids.dart';

final lowercaseFormatter = TextInputFormatter.withFunction(
  (_, value) => value.copyWith(text: value.text.toLowerCase()),
);

final usernameCharsFormatter = FilteringTextInputFormatter.allow(
  RegExp('[$matrixLocalpartChars]'),
);
