import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/session_display_name.dart';

void main() {
  test('title-cases a plain OS name', () {
    expect(sessionDisplayName('android'), 'Zuno on Android');
    expect(sessionDisplayName('linux'), 'Zuno on Linux');
  });

  test('special-cases the two OS names that title-case oddly', () {
    expect(sessionDisplayName('ios'), 'Zuno on iOS');
    expect(sessionDisplayName('macos'), 'Zuno on macOS');
  });

  test('falls back to "Unknown" for an empty OS name', () {
    expect(sessionDisplayName(''), 'Zuno on Unknown');
  });
}
