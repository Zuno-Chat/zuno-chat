import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/background_restrictions.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/native_method_calls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/background_restrictions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final restrictions = BackgroundRestrictions.instance;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final (method, invoke)
      in <(String, Future<void> Function(BackgroundRestrictions))>[
        (
          'requestIgnoreBatteryOptimizations',
          (r) => r.requestIgnoreBatteryOptimizations(),
        ),
        ('openBackgroundDataSettings', (r) => r.openBackgroundDataSettings()),
        ('openAutostartSettings', (r) => r.openAutostartSettings()),
      ]) {
    test('invokes $method on the native channel', () async {
      final native = recordMethodChannel(channel.name);

      await invoke(restrictions);

      expect(native.methods, [method]);
    });
  }

  for (final (method, ask)
      in <(String, Future<bool> Function(BackgroundRestrictions))>[
        (
          'isIgnoringBatteryOptimizations',
          (r) => r.isIgnoringBatteryOptimizations(),
        ),
        ('isBackgroundDataRestricted', (r) => r.isBackgroundDataRestricted()),
        ('hasAutostartSettings', (r) => r.hasAutostartSettings()),
      ]) {
    test('$method returns the native answer, and false for none', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, method);
        return true;
      });
      expect(await ask(restrictions), isTrue);

      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await ask(restrictions), isFalse);
    });
  }

  test(
    'asks whether another package is exempt from battery optimizations',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return false;
      });

      final exempt = await restrictions.isPackageIgnoringBatteryOptimizations(
        'io.heckel.ntfy',
      );

      expect(exempt, isFalse);
      expect(received?.method, 'isPackageIgnoringBatteryOptimizations');
      expect(received?.arguments, {'package': 'io.heckel.ntfy'});
    },
  );

  test('treats a missing native answer as not exempt', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(
      await restrictions.isPackageIgnoringBatteryOptimizations(
        'io.heckel.ntfy',
      ),
      isFalse,
    );
  });

  test('opens the app settings page of another package', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await restrictions.openAppSettings('io.heckel.ntfy');

    expect(received?.method, 'openAppSettings');
    expect(received?.arguments, {'package': 'io.heckel.ntfy'});
  });

  test('autostart settings are not offered when the native side cannot '
      'tell', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await restrictions.hasAutostartSettings(), isFalse);
  });

  group('on a platform without these Android settings', () {
    final ios = BackgroundRestrictions(
      capabilities: capabilitiesFor(AppPlatform.ios),
    );

    test('never reaches the native channel', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return true;
      });

      await ios.isIgnoringBatteryOptimizations();
      await ios.requestIgnoreBatteryOptimizations();
      await ios.isPackageIgnoringBatteryOptimizations('io.heckel.ntfy');
      await ios.openAppSettings('io.heckel.ntfy');
      await ios.isBackgroundDataRestricted();
      await ios.openBackgroundDataSettings();
      await ios.hasAutostartSettings();
      await ios.openAutostartSettings();

      expect(methods, isEmpty);
    });

    test('reports nothing for the user to fix', () async {
      expect(await ios.isIgnoringBatteryOptimizations(), isTrue);
      expect(
        await ios.isPackageIgnoringBatteryOptimizations('io.heckel.ntfy'),
        isTrue,
      );
      expect(await ios.isBackgroundDataRestricted(), isFalse);
      expect(await ios.hasAutostartSettings(), isFalse);
    });
  });
}
