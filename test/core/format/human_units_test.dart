import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/format/human_units.dart';

void main() {
  test('formatBytes picks the unit by size', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  group('formatDuration', () {
    test('under an hour is minutes and padded seconds', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
      expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('from an hour adds the hours and pads the minutes', () {
      expect(formatDuration(const Duration(hours: 1)), '1:00:00');
      expect(formatDuration(const Duration(minutes: 65)), '1:05:00');
      expect(formatDuration(const Duration(hours: 12, seconds: 3)), '12:00:03');
    });

    test('a negative duration, from clock skew, shows as zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
      expect(formatDuration(const Duration(hours: -2)), '0:00');
    });
  });
}
