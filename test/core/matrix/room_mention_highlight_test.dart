import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/room_mention_highlight.dart';

void main() {
  const color = Color(0xFF6750A4);
  const hex = '#6750a4';

  test('wraps a standalone @room mention in a colored, bold span', () {
    final result = highlightRoomMentionsInHtml(
      '<p>@room please read this</p>',
      color,
    );
    expect(
      result,
      '<p><span style="color: $hex; font-weight: bold;">@room</span> please read this</p>',
    );
  });

  test("doesn't touch @room-like substrings inside a longer word", () {
    final result = highlightRoomMentionsInHtml(
      '<p>ask your @roommate about it</p>',
      color,
    );
    expect(result, '<p>ask your @roommate about it</p>');
  });

  test("doesn't rewrite a match that falls inside a tag's attributes", () {
    final result = highlightRoomMentionsInHtml(
      '<a href="https://example.com/@room">link</a>',
      color,
    );
    expect(result, '<a href="https://example.com/@room">link</a>');
  });

  test('highlights every standalone mention when there are several', () {
    final result = highlightRoomMentionsInHtml(
      '<p>@room and @room again</p>',
      color,
    );
    expect('span'.allMatches(result).length, 4);
    expect(result.contains('>@room</span> and'), isTrue);
  });

  group('highlightUserMentionsInHtml', () {
    const blue = Color(0xFF0000FF);

    test(
      'turns a matrix.to user pill into a bold coloured span, not a link',
      () {
        final out = highlightUserMentionsInHtml(
          'hi <a href="https://matrix.to/#/@alice:example.org">@Alice</a>!',
          blue,
        );

        expect(
          out,
          'hi <span style="color: #0000ff; font-weight: bold;">@Alice</span>!',
        );
        expect(out, isNot(contains('<a')));
      },
    );

    test('a pill spelling out the whole user ID drops the server name', () {
      final out = highlightUserMentionsInHtml(
        'hi <a href="https://matrix.to/#/@alice:example.org">'
        '@alice:example.org</a>!',
        blue,
      );

      expect(
        out,
        'hi <span style="color: #0000ff; font-weight: bold;">@alice</span>!',
      );
    });

    test('leaves ordinary links and room links alone', () {
      const html =
          '<a href="https://example.com">site</a> '
          '<a href="https://matrix.to/#/#room:example.org">room</a>';

      expect(highlightUserMentionsInHtml(html, blue), html);
    });
  });
}
