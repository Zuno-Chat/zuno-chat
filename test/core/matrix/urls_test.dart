import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/async/elapsed.dart';
import 'package:zuno/core/matrix/urls.dart';

void main() {
  group('linksIn', () {
    List<String> links(String text) => [
      for (final link in linksIn(text)) text.substring(link.start, link.end),
    ];

    test('no link in plain text', () {
      expect(links('just some text'), isEmpty);
    });

    test('finds every http(s) link with its place in the text', () {
      const text = 'https://a.example/one and http://b.example/two';
      expect(links(text), ['https://a.example/one', 'http://b.example/two']);
      expect(linksIn(text).first.uri, Uri.parse('https://a.example/one'));
    });

    test('stops at markup around a link', () {
      expect(links('see <https://example.org/page>'), [
        'https://example.org/page',
      ]);
    });

    test('leaves out punctuation that ends the sentence', () {
      expect(links('See https://zuno.chat/privacy.'), [
        'https://zuno.chat/privacy',
      ]);
      expect(links('Really? https://x.org/a?! Yes'), ['https://x.org/a']);
      expect(links("'https://x.org/a', then"), ['https://x.org/a']);
    });

    test('leaves out a bracket the link did not open', () {
      expect(links('(https://x.org/a)'), ['https://x.org/a']);
      expect(links('[https://x.org/a].'), ['https://x.org/a']);
    });

    test('keeps a bracket that belongs to the link', () {
      expect(links('(https://en.wikipedia.org/wiki/Mercury_(planet)).'), [
        'https://en.wikipedia.org/wiki/Mercury_(planet)',
      ]);
      expect(links('https://x.org/a?q=1&b=2#top'), [
        'https://x.org/a?q=1&b=2#top',
      ]);
    });

    test('skips a link with no host', () {
      expect(links('http://:80 and https://.'), isEmpty);
    });

    test('keeps balanced brackets of every kind', () {
      expect(links('https://x.org/a{b}[c](d)'), ['https://x.org/a{b}[c](d)']);
    });

    test('leaves out stray brackets mixed with punctuation', () {
      expect(links('(https://x.org/a(b)).,)]}'), ['https://x.org/a(b)']);
    });

    test('a link trailed by a flood of brackets is found quickly', () {
      final stopwatch = startStopwatch();
      final found = links('https://x.example/${')' * 100000}');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(found, ['https://x.example/']);
    });

    test('a link trailed by a flood of punctuation is found quickly', () {
      final stopwatch = startStopwatch();
      final found = links('https://x.example/(a)${').' * 50000}');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(found, ['https://x.example/(a)']);
    });
  });

  group('isSafeExternalUri', () {
    test('allows the schemes a message link can legitimately use', () {
      expect(isSafeExternalUri(Uri.parse('https://example.org/x')), isTrue);
      expect(isSafeExternalUri(Uri.parse('http://example.org')), isTrue);
      expect(isSafeExternalUri(Uri.parse('mailto:a@example.org')), isTrue);
    });

    test('rejects intent: and custom app schemes', () {
      expect(
        isSafeExternalUri(Uri.parse('intent://evil#Intent;package=com.x;end')),
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
