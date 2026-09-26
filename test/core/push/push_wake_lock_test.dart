import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
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

  group('the FCM push wake lock', () {
    const fcmChannel = MethodChannel('zuno/wake_lock');

    tearDown(() => messenger.setMockMethodCallHandler(fcmChannel, null));

    test('is released through the notifications plugin', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(fcmChannel, (call) async {
        calls.add(call.method);
        return null;
      });
      await releaseFcmPushWakeLock();
      expect(calls, ['releasePush']);
    });

    test('survives the native side throwing', () async {
      messenger.setMockMethodCallHandler(fcmChannel, (call) async {
        throw PlatformException(code: 'NO_LOCK');
      });
      await expectLater(releaseFcmPushWakeLock(), completes);
    });
  });

  group('on a platform without wake locks', () {
    const fcmChannel = MethodChannel('zuno/wake_lock');
    final ios = capabilitiesFor(AppPlatform.ios);
    late List<String> calls;

    setUp(() {
      calls = [];
      for (final lockChannel in [channel, fcmChannel]) {
        messenger.setMockMethodCallHandler(lockChannel, (call) async {
          calls.add('${lockChannel.name} ${call.method}');
          return null;
        });
      }
    });

    tearDown(() => messenger.setMockMethodCallHandler(fcmChannel, null));

    test('releasing either push lock never reaches the native side', () async {
      await releasePushWakeLock(capabilities: ios);
      await releaseFcmPushWakeLock(capabilities: ios);

      expect(calls, isEmpty);
    });
  });
}
