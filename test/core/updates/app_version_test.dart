import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/updates/app_version.dart';

void main() {
  group('buildNumberOf', () {
    test('turns a release version into its build number', () {
      expect(buildNumberOf('1.6.0'), 1006000);
      expect(buildNumberOf('2.10.3'), 2010003);
    });

    test('refuses anything that is not three plain numbers', () {
      for (final text in ['1.6', 'v1.6.0', '1.6.0-rc1', '']) {
        expect(buildNumberOf(text), isNull, reason: text);
      }
    });

    test('refuses a minor or patch above 999', () {
      expect(buildNumberOf('1.1000.0'), isNull);
      expect(buildNumberOf('1.0.1000'), isNull);
    });
  });

  test('versionOfBuild turns a build number back into its version', () {
    expect(versionOfBuild(1006000), '1.6.0');
    expect(versionOfBuild(2010003), '2.10.3');
  });
}
