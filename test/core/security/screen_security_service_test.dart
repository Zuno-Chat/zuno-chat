import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/screen_security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('asks the native side to block or allow screenshots', () async {
    await ScreenSecurityService.instance.setPreventScreenshots(true);
    await ScreenSecurityService.instance.setPreventScreenshots(false);

    expect(calls.map((c) => c.method), [
      'setPreventScreenshots',
      'setPreventScreenshots',
    ]);
    expect(calls.map((c) => c.arguments), [
      {'enabled': true},
      {'enabled': false},
    ]);
  });

  test('no native side at all is not an error', () async {
    messenger.setMockMethodCallHandler(channel, null);

    await expectLater(
      ScreenSecurityService.instance.setPreventScreenshots(true),
      completes,
    );
  });

  test('a platform without screen security never calls native', () async {
    final service = ScreenSecurityService(
      capabilities: capabilitiesFor(AppPlatform.ios),
    );

    await service.setPreventScreenshots(true);

    expect(calls, isEmpty);
  });
}
