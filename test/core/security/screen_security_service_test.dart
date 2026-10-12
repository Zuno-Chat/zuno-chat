import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/screen_security_service.dart';

import '../../helpers/fake_calls_channel.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordedMethodCalls native;
  late ScreenSecurityService service;

  setUp(() {
    native = installFakeCallsChannel();
    service = ScreenSecurityService();
  });

  test('follows the preference to block or allow screenshots', () async {
    await service.followPreference(true);
    await service.followPreference(false);

    expect(native.screenshotBlocking, [true, false]);
  });

  test('a protected screen blocks screenshots the preference allows, and '
      'closing it allows them again', () async {
    await service.followPreference(false);
    native.clear();

    final release = service.protect();
    expect(native.screenshotBlocking, [true]);

    release();
    expect(native.screenshotBlocking, [true, false]);
  });

  test('the block stays until the last protected screen closes', () async {
    await service.followPreference(false);
    native.clear();

    final first = service.protect();
    final second = service.protect();
    first();
    first();

    expect(native.screenshotBlocking, [true]);

    second();

    expect(native.screenshotBlocking, [true, false]);
  });

  test('turning the preference off while a screen is protected keeps the '
      'block until it closes', () async {
    await service.followPreference(true);
    final release = service.protect();
    native.clear();

    await service.followPreference(false);
    expect(native.screenshotBlocking, [true]);

    release();
    expect(native.screenshotBlocking, [true, false]);
  });

  test(
    'closing a protected screen keeps the block the preference wants',
    () async {
      await service.followPreference(true);
      final release = service.protect();
      native.clear();

      release();

      expect(native.screenshotBlocking, [true]);
    },
  );

  test('no native side at all is not an error', () async {
    removeCallsChannel();

    await expectLater(service.followPreference(true), completes);
    expect(service.protect, returnsNormally);
  });

  test('a platform without screen security never calls native', () async {
    final service = ScreenSecurityService(
      capabilities: capabilitiesLike(
        androidCapabilities,
        screenSecurity: false,
      ),
    );

    await service.followPreference(true);
    service.protect()();

    expect(native.calls, isEmpty);
  });
}
