import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/background_sync_service.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/native_method_calls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/background_sync');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = BackgroundSyncService.instance;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final (method, invoke)
      in <(String, Future<void> Function(BackgroundSyncService))>[
        ('startBackgroundSyncService', (s) => s.start()),
        ('stopBackgroundSyncService', (s) => s.stop()),
        (
          'requestIgnoreBatteryOptimizations',
          (s) => s.requestIgnoreBatteryOptimizations(),
        ),
        ('openBackgroundDataSettings', (s) => s.openBackgroundDataSettings()),
        ('openAutostartSettings', (s) => s.openAutostartSettings()),
      ]) {
    test('invokes $method on the native channel', () async {
      final native = recordMethodChannel(channel.name);

      await invoke(service);

      expect(native.methods, [method]);
    });
  }

  for (final (method, ask)
      in <(String, Future<bool> Function(BackgroundSyncService))>[
        (
          'isIgnoringBatteryOptimizations',
          (s) => s.isIgnoringBatteryOptimizations(),
        ),
        ('isBackgroundDataRestricted', (s) => s.isBackgroundDataRestricted()),
        ('hasAutostartSettings', (s) => s.hasAutostartSettings()),
      ]) {
    test('$method returns the native answer, and false for none', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, method);
        return true;
      });
      expect(await ask(service), isTrue);

      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await ask(service), isFalse);
    });
  }

  test(
    'start() propagates a PlatformException instead of swallowing it',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(() => service.start(), throwsA(isA<PlatformException>()));
    },
  );

  test(
    'asks whether another package is exempt from battery optimizations',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return false;
      });

      final exempt = await service.isPackageIgnoringBatteryOptimizations(
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
      await service.isPackageIgnoringBatteryOptimizations('io.heckel.ntfy'),
      isFalse,
    );
  });

  test('opens the app settings page of another package', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await service.openAppSettings('io.heckel.ntfy');

    expect(received?.method, 'openAppSettings');
    expect(received?.arguments, {'package': 'io.heckel.ntfy'});
  });

  test('autostart settings are not offered when the native side cannot '
      'tell', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await service.hasAutostartSettings(), isFalse);
  });

  group('on a platform without these Android settings', () {
    final ios = BackgroundSyncService(
      capabilities: capabilitiesFor(AppPlatform.ios),
    );

    test('never reaches the native channel', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return true;
      });

      await ios.start();
      await ios.stop();
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
