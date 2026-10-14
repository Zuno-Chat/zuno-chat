import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/room_name_check.dart';

void main() {
  String? nameError(String name) => roomNameError(englishLocalizations, name);

  test('a room cannot be named after Zuno, and is told so', () {
    expect(nameError('Zuno'), 'Names cannot include Zuno');
    expect(nameError('zuno'), isNotNull);
    expect(nameError('ZUNO'), isNotNull);
  });

  test('a zero standing in for the letter does not get around it', () {
    expect(nameError('Zun0'), isNotNull);
    expect(nameError('ZUN0 support'), isNotNull);
  });

  test('the word is refused anywhere in the name', () {
    expect(nameError('Official zuno team'), isNotNull);
    expect(nameError('myzunogroup'), isNotNull);
  });

  test('names that merely look similar are allowed', () {
    expect(nameError('Zunami'), isNull);
    expect(nameError('Zen'), isNull);
    expect(nameError('Sunday hikers'), isNull);
  });

  test('an empty name is not this check to make', () {
    expect(nameError(''), isNull);
  });
}
