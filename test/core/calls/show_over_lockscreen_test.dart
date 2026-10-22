import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/show_over_lockscreen.dart';

import '../../helpers/fake_calls_channel.dart';
import '../../helpers/native_method_calls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordedMethodCalls native;
  final display = ShowOverLockscreen.instance;

  setUp(() => native = installFakeCallsChannel());

  List<Object?> shows() => [
    for (final args in native.argsOf('setShowOverLockscreen'))
      (args! as Map)['show'],
  ];

  test('shows over the lock screen from the first claim to the last '
      'release, telling native only at those two moments', () async {
    final ring = Object();
    final call = Object();

    display.claim(ring);
    display.claim(call);
    display.release(ring);
    await pumpEventQueue();
    expect(shows(), [true]);

    display.release(call);
    await pumpEventQueue();
    expect(shows(), [true, false]);
  });

  test('a release from an owner that never claimed changes nothing', () async {
    final call = Object();
    display.claim(call);

    display.release(Object());
    await pumpEventQueue();

    expect(shows(), [true]);
    expect(display.claimed, isTrue);
  });

  test('a release for the native launch only goes out while nothing claims '
      'it', () async {
    final ring = Object();
    display.claim(ring);
    await display.releaseUnclaimed();
    expect(shows(), [true]);

    display.release(ring);
    await display.releaseUnclaimed();
    expect(shows(), [true, false, false]);
  });
}
