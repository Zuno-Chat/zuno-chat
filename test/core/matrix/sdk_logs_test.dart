import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/sdk_logs.dart';

void main() {
  tearDown(() => Logs().onLog = null);

  test('the SDK keeps no history of what it logs', () {
    keepNoSdkLogHistory();

    Logs().v('Decrypted to_device event is: {"geo_uri":"geo:1,2"}');
    Logs().w('a warning');

    expect(Logs().outputEvents, isEmpty);
  });
}
