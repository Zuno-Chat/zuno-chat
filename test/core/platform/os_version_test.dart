import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/os_version.dart';

void main() {
  group('osAtLeast', () {
    test('compares an iOS version string with a minimum', () {
      expect(osAtLeast('Version 18.2 (Build 22C152)', '18.0'), isTrue);
      expect(osAtLeast('Version 18.2 (Build 22C152)', '18.2'), isTrue);
      expect(osAtLeast('Version 18.2 (Build 22C152)', '18.4'), isFalse);
      expect(osAtLeast('Version 26.0 (Build 23A5)', '18.0'), isTrue);
      expect(osAtLeast('Version 18.2.1 (Build 22C161)', '18.2.2'), isFalse);
    });

    test('is false when either side does not parse', () {
      expect(osAtLeast('unknown', '18.0'), isFalse);
      expect(osAtLeast('Version 18.2', 'garbage'), isFalse);
    });
  });

  test('osVersionParts reads up to three numbers and pads the rest', () {
    expect(osVersionParts('Version 18.2 (Build 22C152)'), [18, 2, 0]);
    expect(osVersionParts('17'), [17, 0, 0]);
    expect(osVersionParts('none'), isNull);
  });
}
