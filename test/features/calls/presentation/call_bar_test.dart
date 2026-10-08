import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_status.dart';
import 'package:zuno/features/calls/presentation/call_bar.dart';

void main() {
  test('a call in progress shows its timer, not a label', () {
    expect(callBarLabel(CallStatus.talking, reconnecting: false), isNull);
  });

  test('reconnecting outranks everything', () {
    expect(
      callBarLabel(CallStatus.talking, reconnecting: true),
      'Reconnecting…',
    );
  });

  test('a call whose keys have not arrived says so instead of counting', () {
    expect(
      callBarLabel(CallStatus.encrypting, reconnecting: false),
      'Encrypting…',
    );
  });

  test('each waiting state has its own short word', () {
    expect(callBarLabel(CallStatus.calling, reconnecting: false), 'Calling…');
    expect(
      callBarLabel(CallStatus.connecting, reconnecting: false),
      'Connecting…',
    );
    expect(callBarLabel(CallStatus.waiting, reconnecting: false), 'Waiting…');
  });
}
