import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/format/human_units.dart';

void main() {
  test('formatBytes picks the unit by size', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('formatClock renders minutes and zero-padded seconds', () {
    expect(formatClock(const Duration(seconds: 42)), '0:42');
    expect(formatClock(const Duration(minutes: 61, seconds: 5)), '61:05');
  });
}
