import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/security/verification_signaling.dart';

void main() {
  test('every step of the flow is hidden, from the request on', () {
    for (final type in [
      EventTypes.KeyVerificationRequest,
      EventTypes.KeyVerificationStart,
      EventTypes.KeyVerificationReady,
      EventTypes.KeyVerificationAccept,
      EventTypes.KeyVerificationCancel,
      EventTypes.KeyVerificationDone,
    ]) {
      expect(isVerificationSignalingMessage(type), isTrue, reason: type);
    }
  });

  test('ordinary messages are untouched', () {
    expect(isVerificationSignalingMessage(MessageTypes.Text), isFalse);
    expect(isVerificationSignalingMessage(MessageTypes.Image), isFalse);
    expect(isVerificationSignalingMessage(null), isFalse);
    expect(isVerificationSignalingMessage('m.key.verificationish'), isFalse);
  });
}
