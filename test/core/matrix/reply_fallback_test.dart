import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/reply_fallback.dart';

void main() {
  test('leaves plain text without a quote untouched', () {
    expect(stripReplyFallback('just a message'), 'just a message');
  });

  test('strips a classic single-line reply quote', () {
    expect(
      stripReplyFallback(
        '> <@alice:example.org> the original text\n\nmy reply',
      ),
      'my reply',
    );
  });

  test('strips a multi-line quote (several "> " lines)', () {
    expect(
      stripReplyFallback(
        '> <@alice:example.org> line one\n> line two\n\nmy reply',
      ),
      'my reply',
    );
  });

  test('a body that is only a quote, with no reply text, strips to empty', () {
    expect(stripReplyFallback('> <@alice:example.org> only a quote'), '');
  });
}
