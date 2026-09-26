import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/media_processing_exception.dart';

void main() {
  test('reads as its message wherever it is shown', () {
    const error = MediaProcessingException('Could not read this video.');

    expect('$error', 'Could not read this video.');
    expect(error.message, 'Could not read this video.');
  });
}
