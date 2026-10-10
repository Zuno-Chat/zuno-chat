import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/picker_access.dart';

void main() {
  test('a camera or photo library the person did not allow is a refusal', () {
    for (final code in ['camera_access_denied', 'photo_access_denied']) {
      expect(
        isPickerAccessDenied(PlatformException(code: code)),
        isTrue,
        reason: code,
      );
    }
  });

  test('a picker that fails any other way is not', () {
    for (final error in <Object>[
      PlatformException(code: 'no_available_camera'),
      PlatformException(code: 'multiple_request'),
      StateError('camera_access_denied'),
    ]) {
      expect(isPickerAccessDenied(error), isFalse, reason: '$error');
    }
  });
}
