import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowed = {
  'lib/core/matrix/sync_coordinator.dart',
  'lib/core/matrix/zuno_client.dart',
  'lib/core/matrix/matrix_client_provider.dart',
};

final _syncControl = RegExp(
  r'\.(backgroundSync\s*=|abortSync\(|oneShotSync\()',
);

void main() {
  test('only the sync coordinator drives the app client\'s sync', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !_allowed.contains(file.path))
        .where((file) => _syncControl.hasMatch(file.readAsStringSync()))
        .map((file) => file.path);

    expect(offenders, isEmpty);
  });
}
