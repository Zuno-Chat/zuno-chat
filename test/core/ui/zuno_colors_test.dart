import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_colors.dart';

import '../../helpers/contrast.dart';

void main() {
  test('pinned outputs: the hash cannot change and recolor everyone', () {
    expect(avatarToneFor(''), avatarTones[1]);
    expect(avatarToneFor('maya'), avatarTones[4]);
    expect(avatarToneFor('@maya:zuno.chat'), avatarTones[6]);
    expect(avatarToneFor('!abc:zuno.chat'), avatarTones[5]);
    expect(avatarToneFor('Оксана'), avatarTones[2]);
  });

  test('400 similar IDs spread evenly over the tones', () {
    final counts = <Color, int>{};
    for (var i = 0; i < 400; i++) {
      final tone = avatarToneFor('@user$i:zuno.chat');
      counts[tone] = (counts[tone] ?? 0) + 1;
    }
    expect(counts, hasLength(8));
    for (final count in counts.values) {
      expect(count, inInclusiveRange(30, 70));
    }
  });

  test('ink initials are readable on every tone', () {
    for (final tone in avatarTones) {
      expect(contrastRatio(zunoInk, tone), greaterThanOrEqualTo(4.5));
    }
  });

  test('both bubble text tokens are readable on the bubble', () {
    for (final colors in [ZunoColors.light, ZunoColors.dark]) {
      expect(
        contrastRatio(colors.onBubbleOutgoing, colors.bubbleOutgoing),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.onBubbleOutgoingVariant, colors.bubbleOutgoing),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('links are readable on the outgoing bubble', () {
    for (final colors in [ZunoColors.light, ZunoColors.dark]) {
      expect(
        contrastRatio(colors.link, colors.bubbleOutgoing),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('lerp ends at each side and survives a null other', () {
    expect(
      ZunoColors.light.lerp(ZunoColors.dark, 0).bubbleOutgoing,
      ZunoColors.light.bubbleOutgoing,
    );
    expect(
      ZunoColors.light.lerp(ZunoColors.dark, 1).success,
      ZunoColors.dark.success,
    );
    expect(
      ZunoColors.light.lerp(ZunoColors.dark, 1).link,
      ZunoColors.dark.link,
    );
    expect(ZunoColors.light.lerp(null, 0.5), same(ZunoColors.light));
  });

  test('ofTheme reads the theme\'s own colors, else the default for its brightness', () {
    const own = ZunoColors(
      bubbleOutgoing: Colors.black,
      onBubbleOutgoing: Colors.white,
      onBubbleOutgoingVariant: Colors.white,
      success: Colors.green,
      link: Colors.blue,
    );

    expect(ZunoColors.ofTheme(ThemeData(extensions: const [own])), same(own));
    expect(
      ZunoColors.ofTheme(ThemeData(brightness: Brightness.light)),
      same(ZunoColors.light),
    );
    expect(
      ZunoColors.ofTheme(ThemeData(brightness: Brightness.dark)),
      same(ZunoColors.dark),
    );
  });
}
