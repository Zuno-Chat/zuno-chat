import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/uia_cancel.dart';

import '../../helpers/uia_challenge.dart';

void main() {
  test('a password prompt backed out of is a cancel', () async {
    final uia = UiaRequest<void>(
      request: (_) async => throw uiaPasswordChallenge(),
    );
    await pumpEventQueue();

    uia.cancel();

    expect(isUiaCancel(uia.error!), isTrue);
  });

  test('anything else that fails a request is not', () {
    for (final error in <Object>[
      uiaPasswordChallenge(errcode: 'M_FORBIDDEN'),
      Exception('Request failed'),
      StateError('canceled'),
    ]) {
      expect(isUiaCancel(error), isFalse, reason: '$error');
    }
  });
}
