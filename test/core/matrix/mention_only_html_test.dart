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
