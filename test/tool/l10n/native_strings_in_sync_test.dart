import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/l10n/native_strings.dart';

void main() {
  test('native string files match the ARB files', () {
    final root = Directory.current;
    expect(
      staleFiles(root, buildOutputs(root)),
      isEmpty,
      reason: 'Run: dart run tool/l10n/generate_native.dart',
    );
  });
}
