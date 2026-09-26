import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/device_safety.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zuno/device_safety');

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  test('reports the risks the device names', () async {
    answer((call) async {
      expect(call.method, 'check');
      return ['unlockedBootloader', 'rooted'];
    });

    expect(await checkDeviceSafety(), {
      DeviceRisk.unlockedBootloader,
      DeviceRisk.rooted,
    });
  });

  test('a safe device reports nothing', () async {
    answer((call) async => <String>[]);

    expect(await checkDeviceSafety(), isEmpty);
  });

  test('an unknown risk name is ignored', () async {
    answer((call) async => ['rooted', 'haunted']);

    expect(await checkDeviceSafety(), {DeviceRisk.rooted});
  });

  test('a failing check reports nothing', () async {
    answer((call) async => throw PlatformException(code: 'keystore'));

    expect(await checkDeviceSafety(), isEmpty);
  });

  test('a platform without the check reports nothing', () async {
    expect(await checkDeviceSafety(), isEmpty);
  });

  test('a check that never answers reports nothing', () async {
    answer((call) => Future<Object?>.delayed(const Duration(minutes: 1)));

    expect(
      await checkDeviceSafety(budget: const Duration(milliseconds: 10)),
      isEmpty,
    );
  });

  group('on a platform without the device check', () {
    final ios = capabilitiesFor(AppPlatform.ios);
    late List<String> calls;

    setUp(() {
      calls = [];
      answer((call) async {
        calls.add(call.method);
        return ['unlockedBootloader', 'rooted'];
      });
    });

    test('reports nothing and never asks the native side', () async {
      expect(await checkDeviceSafety(capabilities: ios), isEmpty);
      expect(calls, isEmpty);
    });

    test('the risks provider reports nothing', () async {
      final container = ProviderContainer(
        overrides: [platformCapabilitiesProvider.overrideWithValue(ios)],
      );
      addTearDown(container.dispose);

      expect(await container.read(deviceRisksProvider.future), isEmpty);
      expect(calls, isEmpty);
    });
  });

  test('the risks provider reports what an android device names', () async {
    answer((call) async => ['rooted']);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(deviceRisksProvider.future), {
      DeviceRisk.rooted,
    });
  });
}
