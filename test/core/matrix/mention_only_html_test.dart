import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parseFragment;

import 'package:zuno/core/matrix/mention_only_html.dart';

const _pill = '<a href="https://matrix.to/#/@alice:example.org">@Alice</a>';

bool mentionOnly({required String html, required String body}) =>
    isMentionOnlyHtml(parseFragment(html), body: body);

void main() {
  test('a body whose only markup is mention pills is mention-only', () {
    expect(mentionOnly(html: 'hi $_pill!', body: 'hi @Alice!'), isTrue);
  });

  test('real formatting keeps the HTML path', () {
    expect(
      mentionOnly(html: 'hi <em>there</em> $_pill', body: 'hi there @Alice'),
      isFalse,
    );
    expect(
      mentionOnly(html: '<a href="https://example.com">site</a>', body: 'site'),
      isFalse,
    );
  });

  test('line breaks, a paragraph wrapper and entities are tolerated', () {
    expect(mentionOnly(html: 'a<br>b $_pill', body: 'a\nb @Alice'), isTrue);
    expect(mentionOnly(html: 'a<br />b', body: 'a\nb'), isTrue);
    expect(mentionOnly(html: '<p>hi $_pill</p>', body: 'hi @Alice'), isTrue);
    expect(mentionOnly(html: 'Tom &amp; $_pill', body: 'Tom & @Alice'), isTrue);
  });

  test('a pill is recognised by the same rule the sanitizer uses', () {
    expect(
      mentionOnly(
        html:
            'hi <a href="https://matrix.to/#/%40alice:example.org">@Alice</a>',
        body: 'hi @Alice',
      ),
      isTrue,
    );
    expect(
      mentionOnly(
        html: 'hi <a title="a>b" href="https://matrix.to/#/@alice:example.org">@Alice</a>',
        body: 'hi @Alice',
      ),
      isTrue,
    );
    expect(
      mentionOnly(
        html: 'hi <a href="https://matrix.to/#/@alice:example.org"><b>@Alice</b></a>',
        body: 'hi @Alice',
      ),
      isFalse,
    );
  });

  test('a reply fallback block is ignored', () {
    expect(
      mentionOnly(
        html: '<mx-reply><blockquote>old</blockquote></mx-reply>hi $_pill',
        body: 'hi @Alice',
      ),
      isTrue,
    );
  });

  test('text that differs from the body keeps the HTML path', () {
    expect(mentionOnly(html: 'hi $_pill extra', body: 'hi @Alice'), isFalse);
  });
}
