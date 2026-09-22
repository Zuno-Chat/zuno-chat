import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/features/chat/presentation/message_html_style.dart';

void main() {
  test('links are coloured, not underlined', () {
    final colors = ColorScheme.fromSeed(seedColor: Colors.blue);
    final style = messageHtmlStyle(
      bodyStyle: const TextStyle(fontSize: 15),
      colors: colors,
      link: ZunoColors.light.link,
    );

    expect(style['a']!.textDecoration, TextDecoration.none);
    expect(style['a']!.color, ZunoColors.light.link);
    expect(style['a']!.color, isNot(colors.primary));
  });
}
