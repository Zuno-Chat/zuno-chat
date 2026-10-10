import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/push_wake_lock.dart';

import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/push_wakelock');
  const refinementChannel = MethodChannel('zuno/wake_lock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(refinementChannel, null);
  });

  test('releasing tells the native side to let the CPU sleep, naming the '
      'push the lock was held for', () async {
    final lock = recordMethodChannel(channel.name);

    await releasePushWakeLock(key: r'$event');
    await releasePushWakeLock();

    expect(lock.calls.map((c) => [c.method, c.arguments]), [
      [
        'release',
        {'key': r'$event'},
      ],
      ['release', null],
    ]);
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

  group('whether the app is in front', () {
    test('is asked of the native side', () async {
      for (final answer in [true, false]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'appInFront');
          return answer;
        });
        expect(await nativePushAppInFront(), answer);
      }
    });

    test('counts as in front when the native side cannot say', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'error');
      });
      expect(await nativePushAppInFront(), isTrue);

      messenger.setMockMethodCallHandler(channel, null);
      expect(await nativePushAppInFront(), isTrue);
    });
  });

  group('keepAwakeWhile', () {
    late List<MethodCall> locks;

    setUp(() {
      locks = [];
      messenger.setMockMethodCallHandler(refinementChannel, (call) async {
        locks.add(call);
        return null;
      });
    });

    Map<Object?, Object?> argumentsOf(MethodCall call) =>
        call.arguments as Map<Object?, Object?>;

    test('holds a capped wake lock until the work settles', () async {
      final work = Completer<void>();

      final kept = keepAwakeWhile(work.future);
      await pumpEventQueue();
      expect(locks.map((c) => c.method), ['acquire']);
      expect(
        argumentsOf(locks.single)['timeoutMs'],
        allOf(greaterThan(0), lessThanOrEqualTo(10000)),
      );

      work.complete();
      await kept;
      expect(locks.map((c) => c.method), ['acquire', 'release']);
      expect(argumentsOf(locks.last)['tag'], argumentsOf(locks.first)['tag']);
    });

    test('lets go when the work fails too', () async {
      await expectLater(
        keepAwakeWhile(Future<void>.error(StateError('offline'))),
        throwsStateError,
      );

      expect(locks.map((c) => c.method), ['acquire', 'release']);
    });

    test('gives each piece of work a lock of its own', () async {
      final first = Completer<void>();
      final second = Completer<void>();

      final keptFirst = keepAwakeWhile(first.future);
      final keptSecond = keepAwakeWhile(second.future);
      await pumpEventQueue();
      final tags = locks.map((c) => argumentsOf(c)['tag']).toList();
      expect(tags, hasLength(2));
      expect(tags.first, isNot(tags.last));

      first.complete();
      second.complete();
      await Future.wait([keptFirst, keptSecond]);
    });

    test('a native side that fails never fails the work', () async {
      messenger.setMockMethodCallHandler(refinementChannel, (call) async {
        throw PlatformException(code: 'error');
      });

      await expectLater(keepAwakeWhile(Future<void>.value()), completes);
    });
  });

  group('on a platform without wake locks', () {
    final noLocks = capabilitiesLike(
      androidCapabilities,
      headlessWakeLocks: false,
    );
    late List<String> calls;

    setUp(() {
      calls = [];
      for (final lockChannel in [channel, refinementChannel]) {
        messenger.setMockMethodCallHandler(lockChannel, (call) async {
          calls.add('${lockChannel.name} ${call.method}');
          return null;
        });
      }
    });

    test('releasing the push lock never reaches the native side', () async {
      await releasePushWakeLock(capabilities: noLocks);

      expect(calls, isEmpty);
    });

    test(
      'asking whether the app is in front never reaches it either',
      () async {
        expect(await nativePushAppInFront(capabilities: noLocks), isTrue);

        expect(calls, isEmpty);
      },
    );

    test('work still runs, with no lock taken', () async {
      var ran = false;

      await keepAwakeWhile(
        Future<void>(() => ran = true),
        capabilities: noLocks,
      );

      expect(ran, isTrue);
      expect(calls, isEmpty);
    });
  });
}
