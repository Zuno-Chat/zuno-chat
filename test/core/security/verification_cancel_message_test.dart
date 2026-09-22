import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/verification_cancel_message.dart';

void main() {
  VerificationCancelMessage message(String? code, {String? reason}) =>
      verificationCancelMessage(code: code, reason: reason, isOwnDevice: false);

  test('a plain cancel says cancelled, and says nothing happened', () {
    final result = message('m.user');

    expect(result.title, 'Canceled');
    expect(result.body, contains('Nothing changed'));
    expect(result.isAlarming, isFalse);
  });

  test('a mismatch is not dressed up as an ordinary cancel', () {
    for (final code in [
      'm.key_mismatch',
      'm.mismatched_sas',
      'm.mismatched_commitment',
    ]) {
      final result = message(code);
      expect(result.isAlarming, isTrue, reason: code);
      expect(result.title, contains('did not match'), reason: code);
    }
  });

  test('a timeout reads as a non-event', () {
    expect(message('m.timeout').title, 'Timed out');
    expect(message('m.timeout').isAlarming, isFalse);
  });

  test('no protocol token ever reaches the screen', () {
    for (final code in [
      null,
      'm.unknown',
      'm.unknown_method',
      'm.unexpected_message',
      'm.invalid_message',
      'm.user',
      'm.timeout',
      'm.accepted',
      'something.new.in.a.future.spec',
    ]) {
      final result = message(code, reason: code);
      expect(result.title, isNot(startsWith('m.')), reason: '$code');
      expect(result.body, isNot(startsWith('m.')), reason: '$code');
      expect(result.body, isNot(contains('m.unknown')), reason: '$code');
    }
  });

  test('real prose from the other side is passed through', () {
    expect(
      message('m.unknown', reason: 'The other phone ran out of battery.').body,
      'The other phone ran out of battery.',
    );
  });

  test('own-device copy talks about devices, not people', () {
    final own = verificationCancelMessage(
      code: 'm.key_mismatch',
      reason: null,
      isOwnDevice: true,
    );

    expect(own.body, contains('device'));
    expect(own.body, isNot(contains('they were not')));
  });
}
