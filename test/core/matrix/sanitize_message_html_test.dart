import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/sanitize_message_html.dart';

void main() {
  group('sanitizeMessageHtml', () {
    test('keeps ordinary formatting untouched', () {
      expect(
        sanitizeMessageHtml('<p>hello <strong>there</strong></p>'),
        '<p>hello <strong>there</strong></p>',
      );
    });

    test('keeps an https link, href and all', () {
      expect(
        sanitizeMessageHtml('<a href="https://example.org/x">go</a>'),
        '<a href="https://example.org/x">go</a>',
      );
    });

    test('drops an img entirely, tracking pixel and all', () {
      final out = sanitizeMessageHtml(
        'hi<img src="https://tracker.example/beacon.png?u=victim">',
      );
      expect(out, isNot(contains('img')));
      expect(out, isNot(contains('tracker.example')));
      expect(out, contains('hi'));
    });

    test('drops an img even when nested inside allowed markup', () {
      expect(
        sanitizeMessageHtml('<p><em><img src="http://a.example/b.gif"></em></p>'),
        isNot(contains('a.example')),
      );
    });

    test('drops event handlers and style attributes', () {
      final out = sanitizeMessageHtml(
        '<span onerror="steal()" style="position:fixed" '
        'data-mx-color="#ff0000">x</span>',
      );
      expect(out, isNot(contains('onerror')));
      expect(out, isNot(contains('style')));
      expect(out, contains('data-mx-color'));
    });

    test('drops a javascript: href but keeps the link text', () {
      final out = sanitizeMessageHtml('<a href="javascript:alert(1)">tap</a>');
      expect(out, isNot(contains('javascript')));
      expect(out, contains('tap'));
    });

    test('drops an intent: href', () {
      expect(
        sanitizeMessageHtml(
          '<a href="intent://evil#Intent;package=com.x;end">tap</a>',
        ),
        isNot(contains('intent:')),
      );
    });

    test('unwraps a disallowed tag but keeps its text', () {
      expect(sanitizeMessageHtml('<marquee>keep me</marquee>'), 'keep me');
    });

    test('drops script contents rather than surfacing them as text', () {
      final out = sanitizeMessageHtml('<script>alert(1)</script>after');
      expect(out, isNot(contains('alert')));
      expect(out, contains('after'));
    });

    test('drops a namespaced attribute smuggled through foreign content', () {
      final out = sanitizeMessageHtml(
        '<a xlink:href="javascript:alert(1)" href="https://ok.example">t</a>',
      );
      expect(out, isNot(contains('xlink')));
      expect(out, isNot(contains('javascript')));
      expect(out, contains('https://ok.example'));
    });

    test('drops a code class that is not a language hint', () {
      expect(
        sanitizeMessageHtml('<code class="pwn">x</code>'),
        isNot(contains('pwn')),
      );
      expect(
        sanitizeMessageHtml('<code class="language-dart">x</code>'),
        contains('language-dart'),
      );
    });

    test('survives malformed markup without throwing', () {
      expect(() => sanitizeMessageHtml('<p><b>unclosed'), returnsNormally);
      expect(sanitizeMessageHtml(''), '');
    });

    test('escapes text rather than letting it re-enter as markup', () {
      expect(sanitizeMessageHtml('a < b && c'), isNot(contains('&&')));
    });
  });
}
