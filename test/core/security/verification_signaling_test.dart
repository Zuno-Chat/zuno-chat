import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/security/verification_signaling.dart';

void main() {
  test('the request that put protocol chatter in the timeline is hidden', () {
    expect(
      isVerificationSignalingMessage(EventTypes.KeyVerificationRequest),
      isTrue,
    );
  });

  test('every step of the flow is hidden, not just the request', () {
    for (final type in [
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
