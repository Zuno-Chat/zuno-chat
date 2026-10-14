import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_status.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/features/calls/presentation/call_bar.dart';

void main() {
  String? labelOf(CallStatus status, {bool reconnecting = false}) =>
      callBarLabel(englishLocalizations, status, reconnecting: reconnecting);

  test('a call in progress shows its timer, not a label', () {
    expect(labelOf(CallStatus.talking), isNull);
  });

  test('reconnecting outranks everything', () {
    expect(labelOf(CallStatus.talking, reconnecting: true), 'Reconnecting…');
  });

  test('a call whose keys have not arrived says so instead of counting', () {
    expect(labelOf(CallStatus.encrypting), 'Encrypting…');
  });

  test('each waiting state has its own short word', () {
    expect(labelOf(CallStatus.calling), 'Calling…');
    expect(labelOf(CallStatus.connecting), 'Connecting…');
    expect(labelOf(CallStatus.waiting), 'Waiting…');
  });
}
