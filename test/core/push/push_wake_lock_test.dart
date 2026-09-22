import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/push_wake_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/push_wakelock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('releasing tells the native side to let the CPU sleep', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await releasePushWakeLock();
    expect(calls, ['release']);
  });

  group('never takes push handling down with it', () {
    test('survives the channel not being registered at all', () async {
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(releasePushWakeLock(), completes);
    });

    test('survives the native side throwing', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'NO_LOCK', message: 'not held');
      });
      await expectLater(releasePushWakeLock(), completes);
    });
  });
}
