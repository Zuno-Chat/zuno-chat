import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/mention_only_html.dart';

const _pill = '<a href="https://matrix.to/#/@alice:example.org">@Alice</a>';

void main() {
  test('a body whose only markup is mention pills is mention-only', () {
    expect(isMentionOnlyHtml(html: 'hi $_pill!', body: 'hi @Alice!'), isTrue);
  });

  test('real formatting keeps the HTML path', () {
    expect(
      isMentionOnlyHtml(
        html: 'hi <em>there</em> $_pill',
        body: 'hi there @Alice',
      ),
      isFalse,
    );
    expect(
      isMentionOnlyHtml(
        html: '<a href="https://example.com">site</a>',
        body: 'site',
      ),
      isFalse,
    );
  });

  test('line breaks, a paragraph wrapper and entities are tolerated', () {
    expect(
      isMentionOnlyHtml(html: 'a<br>b $_pill', body: 'a\nb @Alice'),
      isTrue,
    );
    expect(isMentionOnlyHtml(html: 'a<br />b', body: 'a\nb'), isTrue);
    expect(
      isMentionOnlyHtml(html: '<p>hi $_pill</p>', body: 'hi @Alice'),
      isTrue,
    );
    expect(
      isMentionOnlyHtml(html: 'Tom &amp; $_pill', body: 'Tom & @Alice'),
      isTrue,
    );
  });

  test('a pill is recognised by the same rule the sanitizer uses', () {
    expect(
      isMentionOnlyHtml(
        html:
            'hi <a href="https://matrix.to/#/%40alice:example.org">@Alice</a>',
        body: 'hi @Alice',
      ),
      isTrue,
    );
    expect(
      isMentionOnlyHtml(
        html: 'hi <a title="a>b" href="https://matrix.to/#/@alice:example.org">@Alice</a>',
        body: 'hi @Alice',
      ),
      isTrue,
    );
    expect(
      isMentionOnlyHtml(
        html: 'hi <a href="https://matrix.to/#/@alice:example.org"><b>@Alice</b></a>',
        body: 'hi @Alice',
      ),
      isFalse,
    );
  });

  test('a reply fallback block is ignored', () {
    expect(
      isMentionOnlyHtml(
        html: '<mx-reply><blockquote>old</blockquote></mx-reply>hi $_pill',
        body: 'hi @Alice',
      ),
      isTrue,
    );
  });

  test('text that differs from the body keeps the HTML path', () {
    expect(
      isMentionOnlyHtml(html: 'hi $_pill extra', body: 'hi @Alice'),
      isFalse,
    );
  });
}
