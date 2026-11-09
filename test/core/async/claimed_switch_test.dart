import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/async/claimed_switch.dart';

class _RecordedSwitch extends ClaimedSwitch {
  final sent = <bool>[];

  @override
  Future<void> send(bool on) async => sent.add(on);
}

void main() {
  late _RecordedSwitch light;

  setUp(() => light = _RecordedSwitch());

  test('the first claim switches it on and the last release switches it '
      'off', () {
    final call = Object();
    final recording = Object();

    light.claim(call);
    light.claim(recording);
    light.release(call);
    expect(light.sent, [true]);
    expect(light.claimed, isTrue);

    light.release(recording);
    expect(light.sent, [true, false]);
    expect(light.claimed, isFalse);
  });

  test('claiming twice or releasing what was never claimed changes '
      'nothing', () {
    final owner = Object();

    light.release(owner);
    light.claim(owner);
    light.claim(owner);
    expect(light.sent, [true]);

    light.release(Object());
    light.release(owner);
    light.release(owner);
    expect(light.sent, [true, false]);
  });
}
