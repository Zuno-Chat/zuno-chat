import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/push/delivery/push_status_action.dart';

void main() {
  test('register and retry get their button, and nothing else does, since a '
      'fix gets its own row', () {
    expect(
      pushStatusActionLabel(englishLocalizations, PushStatusAction.register),
      englishLocalizations.notificationsRegister,
    );
    expect(
      pushStatusActionLabel(englishLocalizations, PushStatusAction.retry),
      englishLocalizations.commonRetry,
    );
    expect(
      pushStatusActionLabel(englishLocalizations, PushStatusAction.none),
      isNull,
    );
    expect(
      pushStatusActionLabel(englishLocalizations, PushStatusAction.fix),
      isNull,
    );
  });
}
