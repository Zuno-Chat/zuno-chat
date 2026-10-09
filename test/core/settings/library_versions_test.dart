import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/settings/library_versions.dart';

const _matrix = '''
  matrix:
    dependency: "direct main"
    description:
      name: matrix
      url: "https://pub.dev"
    source: hosted
    version: "13.0.0"
''';

const _vodozemac = '''
  vodozemac:
    dependency: "direct main"
    description:
      name: vodozemac
      url: "https://pub.dev"
    source: hosted
    version: "0.8.0"
''';

void main() {
  test('reads the chat and encryption library versions from the lock', () {
    expect(parseLibraryVersions('packages:\n$_matrix$_vodozemac'), (
      matrix: '13.0.0',
      vodozemac: '0.8.0',
    ));
  });

  test('a library missing from the lock is an error, not another version', () {
    expect(
      () => parseLibraryVersions('packages:\n$_vodozemac'),
      throwsFormatException,
    );
  });

  test('a library entry without a version is an error', () {
    final matrixWithoutVersion = _matrix.replaceFirst(
      '    version: "13.0.0"\n',
      '',
    );

    expect(
      () => parseLibraryVersions('packages:\n$matrixWithoutVersion$_vodozemac'),
      throwsFormatException,
    );
  });
}
