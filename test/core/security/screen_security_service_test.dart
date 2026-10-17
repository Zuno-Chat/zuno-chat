import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/screen_security_service.dart';

import '../../helpers/fake_privacy_channel.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordedMethodCalls native;
  late ScreenSecurityService service;

  setUp(() {
    native = installFakePrivacyChannel();
    service = ScreenSecurityService(capabilities: androidCapabilities);
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

  group('other apps drawn over Zuno', () {
    test('are hidden only while a protected screen shows', () async {
      await service.followPreference(true);
      expect(native.overlayHiding, isEmpty);

      final first = service.protect();
      final second = service.protect();
      first();
      expect(native.overlayHiding, [true]);

      second();
      expect(native.overlayHiding, [true, false]);
    });

    test('are left alone where the platform has no such apps', () async {
      final service = ScreenSecurityService(capabilities: iosCapabilities);
      await service.followPreference(false);

      service.protect()();

      expect(native.overlayHiding, isEmpty);
      expect(native.screenshotBlocking, [false, true, false]);
    });
  });

  group('accessibility services', () {
    test('are kept out from the start', () async {
      await service.start(preventScreenshots: false);

      expect(native.accessibilitySensitivity, [true]);
      expect(native.screenshotBlocking, [false]);
    });

    test('are let in while a sign-in screen shows, until the last one '
        'closes', () async {
      final first = service.allowAccessibilityServices();
      final second = service.allowAccessibilityServices();
      first();
      first();
      expect(native.accessibilitySensitivity, [false]);

      second();
      expect(native.accessibilitySensitivity, [false, true]);
    });

    test(
      'stay let in when a sign-in screen is already open at start',
      () async {
        service.allowAccessibilityServices();
        native.clear();

        await service.start(preventScreenshots: true);

        expect(native.accessibilitySensitivity, [false]);
      },
    );

    test('changing the screenshot preference leaves them alone', () async {
      await service.followPreference(false);
      service.protect()();

      expect(native.accessibilitySensitivity, isEmpty);
    });

    test('are never touched where the platform has none to keep out', () async {
      final service = ScreenSecurityService(capabilities: iosCapabilities);

      await service.start(preventScreenshots: true);
      service.allowAccessibilityServices()();

      expect(native.accessibilitySensitivity, isEmpty);
    });
  });

  test('no native side at all is not an error', () async {
    removePrivacyChannel();

    await expectLater(service.start(preventScreenshots: true), completes);
    expect(service.protect, returnsNormally);
    expect(service.allowAccessibilityServices, returnsNormally);
  });

  test('a platform without screen security never calls native', () async {
    final service = ScreenSecurityService(
      capabilities: capabilitiesLike(
        androidCapabilities,
        screenSecurity: false,
        overlayHiding: false,
        accessibilitySensitivity: false,
      ),
    );

    await service.start(preventScreenshots: true);
    service.protect()();
    service.allowAccessibilityServices()();

    expect(native.calls, isEmpty);
  });
}
