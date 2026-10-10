import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/calls/presentation/call_window.dart';

void main() {
  const area = Size(360, 640);
  const padding = EdgeInsets.only(top: 24, bottom: 16);

  test('the window stays clear of the app bar, the system bars and the '
      'keyboard', () {
    expect(
      callWindowBounds(area, padding: padding, viewInsets: EdgeInsets.zero),
      const Rect.fromLTRB(8, 88, 352, 616),
    );
    expect(
      callWindowBounds(
        area,
        padding: padding,
        viewInsets: const EdgeInsets.only(bottom: 300),
      ).bottom,
      332,
    );
  });

  test('the window keeps clear of the bottom bar, above the keyboard too', () {
    expect(
      callWindowBounds(
        area,
        padding: padding,
        viewInsets: EdgeInsets.zero,
        keepClear: 80,
      ).bottom,
      640 - 80 - 8,
    );
    expect(
      callWindowBounds(
        area,
        padding: padding,
        viewInsets: const EdgeInsets.only(bottom: 300),
        keepClear: 60,
      ).bottom,
      640 - 300 - 60 - 8,
    );
  });

  test('the window is a third of the short side, shaped like the video', () {
    expect(
      callWindowSize(const Size(360, 640), (width: 3, height: 4)),
      const Size(108, 144),
    );
    expect(
      callWindowSize(const Size(1000, 2000), (width: 239, height: 100)),
      const Size(160, 90),
    );
  });
}
