import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/notifications/pusher_failure.dart';

void main() {
  test('each failure renders in the language it is shown in', () {
    expect(
      const PusherServerMissing().message(englishLocalizations),
      'No server to send notifications through yet.',
    );
    expect(
      const PusherPostFailed('M_FORBIDDEN').message(englishLocalizations),
      'M_FORBIDDEN',
    );
    expect(
      const PusherRemoveFailed('M_UNKNOWN').message(englishLocalizations),
      'Could not remove the push registration: M_UNKNOWN',
    );
  });

  test('a failure keeps its raw detail, not rendered text', () {
    expect(const PusherRemoveFailed('M_UNKNOWN').detail, 'M_UNKNOWN');
  });
}
