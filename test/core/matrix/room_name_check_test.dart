import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/room_name_check.dart';

void main() {
  test('a room cannot be named after Zuno', () {
    expect(roomNameError('Zuno'), isNotNull);
    expect(roomNameError('zuno'), isNotNull);
    expect(roomNameError('ZUNO'), isNotNull);
  });

  test('a zero standing in for the letter does not get around it', () {
    expect(roomNameError('Zun0'), isNotNull);
    expect(roomNameError('ZUN0 support'), isNotNull);
  });

  test('the word is refused anywhere in the name', () {
    expect(roomNameError('Official zuno team'), isNotNull);
    expect(roomNameError('myzunogroup'), isNotNull);
  });

  test('names that merely look similar are allowed', () {
    expect(roomNameError('Zunami'), isNull);
    expect(roomNameError('Zen'), isNull);
    expect(roomNameError('Sunday hikers'), isNull);
  });

  test('an empty name is not this check to make', () {
    expect(roomNameError(''), isNull);
  });

  test('the refusal names the word it refuses', () {
    expect(roomNameError('Zuno'), contains('Zuno'));
  });
}
