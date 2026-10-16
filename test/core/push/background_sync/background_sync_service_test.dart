import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/background_sync/background_sync_service.dart';

import '../../../helpers/native_method_calls.dart';

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
      ]) {
    test('invokes $method on the native channel', () async {
      final native = recordMethodChannel(channel.name);

      await invoke(service);

      expect(native.methods, [method]);
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

  test('on a platform without the sync service it never reaches the native '
      'channel', () async {
    final ios = BackgroundSyncService(
      capabilities: capabilitiesFor(AppPlatform.ios),
    );
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return true;
    });

    await ios.start();
    await ios.stop();

    expect(methods, isEmpty);
  });
}
