import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/settings/presentation/session_key_format.dart';

void main() {
  for (final (name, key, formatted) in [
    ('empty string formats to empty string', '', ''),
    ('groups exactly into 4-character chunks', 'abcdefgh', 'abcd efgh'),
    (
      'a final partial group is kept, not dropped or padded',
      'abcdefghi',
      'abcd efgh i',
    ),
    ('shorter than one group stays as-is', 'abc', 'abc'),
  ]) {
    test(name, () => expect(formatSessionKey(key), formatted));
  }
}
