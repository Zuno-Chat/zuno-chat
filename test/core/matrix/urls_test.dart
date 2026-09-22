import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/urls.dart';

void main() {
  test('no link in plain text', () {
    expect(firstLinkIn('just some text'), isNull);
  });

  test('finds a single http(s) link', () {
    expect(
      firstLinkIn('check this out: https://example.org/page'),
      Uri.parse('https://example.org/page'),
    );
  });

  test('finds only the first of several links', () {
    expect(
      firstLinkIn('https://a.example/one and https://b.example/two'),
      Uri.parse('https://a.example/one'),
    );
  });

  test('a link glued to trailing punctuation/markup is not swallowed', () {
    expect(
      firstLinkIn('see <https://example.org/page>'),
      Uri.parse('https://example.org/page'),
    );
  });

  group('isSafeExternalUri', () {
    test('allows the schemes a message link can legitimately use', () {
      expect(isSafeExternalUri(Uri.parse('https://example.org/x')), isTrue);
      expect(isSafeExternalUri(Uri.parse('http://example.org')), isTrue);
      expect(isSafeExternalUri(Uri.parse('mailto:a@example.org')), isTrue);
    });

    test('rejects intent: and custom app schemes', () {
      expect(
        isSafeExternalUri(
          Uri.parse('intent://evil#Intent;package=com.x;end'),
        ),
        isFalse,
      );
      expect(isSafeExternalUri(Uri.parse('myapp://do-something')), isFalse);
    });

    test('rejects javascript: and file:', () {
      expect(isSafeExternalUri(Uri.parse('javascript:alert(1)')), isFalse);
      expect(isSafeExternalUri(Uri.parse('file:///etc/passwd')), isFalse);
    });

    test('rejects an http(s) URI with no host', () {
      expect(isSafeExternalUri(Uri.parse('https:evil')), isFalse);
      expect(isSafeExternalUri(Uri.parse('mailto:')), isFalse);
    });

    test('is case-insensitive about the scheme', () {
      expect(isSafeExternalUri(Uri.parse('HTTPS://example.org')), isTrue);
    });
  });
}
