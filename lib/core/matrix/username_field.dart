import 'package:flutter/services.dart';

const signupUsernameChars = 'a-z0-9._';

final lowercaseFormatter = TextInputFormatter.withFunction(
  (_, value) => value.copyWith(text: value.text.toLowerCase()),
);

final usernameCharsFormatter = FilteringTextInputFormatter.allow(
  RegExp('[$signupUsernameChars]'),
);
