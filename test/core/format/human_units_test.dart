import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/format/human_units.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  test('formatBytes picks the unit by size', () {
    expect(formatBytes(englishLocalizations, 512), '512 B');
    expect(formatBytes(englishLocalizations, 2048), '2.0 KB');
    expect(formatBytes(englishLocalizations, 3 * 1024 * 1024), '3.0 MB');
    expect(formatBytes(englishLocalizations, 1023), '1023 B');
    expect(formatBytes(englishLocalizations, 1280), '1.3 KB');
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

  test('joinDetails puts the same separator between every detail', () {
    expect(joinDetails(['Photo', '2.1 MB']), 'Photo · 2.1 MB');
    expect(joinDetails(['Photo']), 'Photo');
    expect(joinDetails(const []), '');
  });
}
