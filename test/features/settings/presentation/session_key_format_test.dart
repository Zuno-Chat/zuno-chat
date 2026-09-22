import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/settings/presentation/session_key_format.dart';

void main() {
  test('empty string formats to empty string', () {
    expect(formatSessionKey(''), '');
  });

  test('groups exactly into 4-character chunks', () {
    expect(formatSessionKey('abcdefgh'), 'abcd efgh');
  });

  test('a final partial group is kept, not dropped or padded', () {
    expect(formatSessionKey('abcdefghi'), 'abcd efgh i');
  });

  test('shorter than one group stays as-is', () {
    expect(formatSessionKey('abc'), 'abc');
  });
}
