import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/screen_security_service.dart';

import '../../helpers/fake_calls_channel.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() => calls = installFakeCallsChannel().calls);

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
    removeCallsChannel();

    await expectLater(
      ScreenSecurityService.instance.setPreventScreenshots(true),
      completes,
    );
  });

  test('a platform without screen security never calls native', () async {
    final service = ScreenSecurityService(
      capabilities: capabilitiesLike(
        androidCapabilities,
        screenSecurity: false,
      ),
    );

    await service.setPreventScreenshots(true);

    expect(calls, isEmpty);
  });
}
