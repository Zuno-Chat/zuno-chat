import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parseFragment;
import 'package:zuno/core/matrix/sanitize_message_html.dart';

const _blue = Color(0xFF0000FF);
const _mention = '<span style="color: #0000ff; font-weight: bold;">';

String sanitize(String html) => sanitizeMessageHtml(html, mentionColor: _blue);

void main() {
  group('sanitizeMessageHtml', () {
    test('keeps ordinary formatting untouched', () {
      expect(
        sanitize('<p>hello <strong>there</strong></p>'),
        '<p>hello <strong>there</strong></p>',
      );
    });

    test('keeps an https link, href and all', () {
      expect(
        sanitize('<a href="https://example.org/x">go</a>'),
        '<a href="https://example.org/x">go</a>',
      );
    });

    test('drops an img entirely, tracking pixel and all', () {
      final out = sanitize(
        'hi<img src="https://tracker.example/beacon.png?u=victim">',
      );
      expect(out, isNot(contains('img')));
      expect(out, isNot(contains('tracker.example')));
      expect(out, contains('hi'));
    });

    test('drops an img even when nested inside allowed markup', () {
      expect(
        sanitize('<p><em><img src="http://a.example/b.gif"></em></p>'),
        isNot(contains('a.example')),
      );
    });

    test('drops event handlers and style attributes', () {
      final out = sanitize(
        '<span onerror="steal()" style="position:fixed" '
        'data-mx-color="#ff0000">x</span>',
      );
      expect(out, isNot(contains('onerror')));
      expect(out, isNot(contains('style')));
      expect(out, contains('data-mx-color'));
    });

    test('drops a javascript: href but keeps the link text', () {
      final out = sanitize('<a href="javascript:alert(1)">tap</a>');
      expect(out, isNot(contains('javascript')));
      expect(out, contains('tap'));
    });

    test('unwraps a disallowed tag but keeps its text', () {
      expect(sanitize('<marquee>keep me</marquee>'), 'keep me');
    });

    test('drops script contents rather than surfacing them as text', () {
      final out = sanitize('<script>alert(1)</script>after');
      expect(out, isNot(contains('alert')));
      expect(out, contains('after'));
    });

    test('drops the reply fallback with everything in it', () {
      expect(
        sanitize(
          '<mx-reply><blockquote><a href="https://matrix.to/#/!r/e">'
          'In reply to</a> earlier</blockquote></mx-reply>now',
        ),
        'now',
      );
    });

    test('drops a namespaced attribute smuggled through foreign content', () {
      final out = sanitize(
        '<a xlink:href="javascript:alert(1)" href="https://ok.example">t</a>',
      );
      expect(out, isNot(contains('xlink')));
      expect(out, isNot(contains('javascript')));
      expect(out, contains('https://ok.example'));
    });

    test('drops a code class that is not a language hint', () {
      expect(sanitize('<code class="pwn">x</code>'), isNot(contains('pwn')));
      expect(
        sanitize('<code class="language-dart">x</code>'),
        contains('language-dart'),
      );
    });

    test('survives malformed markup without throwing', () {
      expect(() => sanitize('<p><b>unclosed'), returnsNormally);
      expect(sanitize(''), '');
    });

    test('escapes text rather than letting it re-enter as markup', () {
      expect(sanitize('a < b && c'), isNot(contains('&&')));
    });
  });

  group('mentions', () {
    test('marks a standalone @room in the mention color', () {
      expect(
        sanitize('<p>@room please read this</p>'),
        '<p>$_mention@room</span> please read this</p>',
      );
    });

    test('marks every @room but not one inside a longer word', () {
      expect(
        sanitize('<p>@room, @roommate and @ROOM</p>'),
        '<p>$_mention@room</span>, @roommate and $_mention@ROOM</span></p>',
      );
    });

    test('never marks @room inside an attribute', () {
      expect(
        sanitize('<a href="https://example.com/@room">link</a>'),
        '<a href="https://example.com/@room">link</a>',
      );
    });

    test('an attribute holding markup never turns into markup', () {
      final out = sanitize(
        '<a href="https://x.com" '
        'title="x>@room <b style=font-size:300px>HUGE</b>">t</a>',
      );

      final reparsed = parseFragment(out);
      expect(reparsed.querySelectorAll('b'), isEmpty);
      expect(reparsed.querySelectorAll('[style]'), isEmpty);
      expect(reparsed.querySelector('a')!.text, 't');
    });

    test('turns a user pill into a marked name, not a link', () {
      expect(
        sanitize(
          'hi <a href="https://matrix.to/#/@alice:example.org">@Alice</a>!',
        ),
        'hi $_mention@Alice</span>!',
      );
    });

    test('a pill spelling out the whole user ID drops the server', () {
      expect(
        sanitize(
          'hi <a href="https://matrix.to/#/%40alice%3Aexample.org" '
          'title="a>b"><em>@alice:example.org</em></a>!',
        ),
        'hi $_mention@alice</span>!',
      );
    });

    test('leaves ordinary links and room links alone', () {
      const html =
          '<a href="https://example.com">site</a> '
          '<a href="https://matrix.to/#/#room:example.org">room</a>';

      expect(sanitize(html), html);
    });
  });
}
