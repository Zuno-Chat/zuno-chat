import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/background_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/background_sync');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'start() invokes startBackgroundSyncService on the native channel',
    () async {
      String? method;
      messenger.setMockMethodCallHandler(channel, (call) async {
        method = call.method;
        return null;
      });
      await BackgroundSyncService.instance.start();
      expect(method, 'startBackgroundSyncService');
    },
  );

  test(
    'stop() invokes stopBackgroundSyncService on the native channel',
    () async {
      String? method;
      messenger.setMockMethodCallHandler(channel, (call) async {
        method = call.method;
        return null;
      });
      await BackgroundSyncService.instance.stop();
      expect(method, 'stopBackgroundSyncService');
    },
  );

  test(
    'start() propagates a PlatformException instead of swallowing it',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(
        () => BackgroundSyncService.instance.start(),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('isIgnoringBatteryOptimizations() returns the native result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isIgnoringBatteryOptimizations');
      return true;
    });
    expect(
      await BackgroundSyncService.instance.isIgnoringBatteryOptimizations(),
      isTrue,
    );
  });

  test(
    'isIgnoringBatteryOptimizations() defaults to false for a null result',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(
        await BackgroundSyncService.instance.isIgnoringBatteryOptimizations(),
        isFalse,
      );
    },
  );

  test(
    'requestIgnoreBatteryOptimizations() invokes the matching native method',
    () async {
      String? method;
      messenger.setMockMethodCallHandler(channel, (call) async {
        method = call.method;
        return null;
      });
      await BackgroundSyncService.instance.requestIgnoreBatteryOptimizations();
      expect(method, 'requestIgnoreBatteryOptimizations');
    },
  );

  test('isBackgroundDataRestricted() returns the native result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isBackgroundDataRestricted');
      return true;
    });
    expect(
      await BackgroundSyncService.instance.isBackgroundDataRestricted(),
      isTrue,
    );
  });

  test(
    'isBackgroundDataRestricted() defaults to false for a null result',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(
        await BackgroundSyncService.instance.isBackgroundDataRestricted(),
        isFalse,
      );
    },
  );

  test(
    'openBackgroundDataSettings() invokes the matching native method',
    () async {
      String? method;
      messenger.setMockMethodCallHandler(channel, (call) async {
        method = call.method;
        return null;
      });
      await BackgroundSyncService.instance.openBackgroundDataSettings();
      expect(method, 'openBackgroundDataSettings');
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

      final exempt = await BackgroundSyncService.instance
          .isPackageIgnoringBatteryOptimizations('io.heckel.ntfy');

      expect(exempt, isFalse);
      expect(received?.method, 'isPackageIgnoringBatteryOptimizations');
      expect(received?.arguments, {'package': 'io.heckel.ntfy'});
    },
  );

  test('treats a missing native answer as not exempt', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);

    expect(
      await BackgroundSyncService.instance
          .isPackageIgnoringBatteryOptimizations('io.heckel.ntfy'),
      isFalse,
    );
  });

  test('opens the app settings page of another package', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await BackgroundSyncService.instance.openAppSettings('io.heckel.ntfy');

    expect(received?.method, 'openAppSettings');
    expect(received?.arguments, {'package': 'io.heckel.ntfy'});
  });
}
