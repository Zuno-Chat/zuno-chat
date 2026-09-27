import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/security/account_security_status.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

const _userId = '@alex:example.org';

const _settled = AccountSecurityFacts(
  recoveryExists: true,
  thisDeviceHasIdentityKeys: true,
  keyBackupExists: true,
  keyBackupUsableHere: true,
  unapprovedOtherDevices: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const backgroundSync = MethodChannel('zuno/background_sync');

  setUp(() {
    messenger.setMockMethodCallHandler(
      permissions,
      (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
    );
    messenger.setMockMethodCallHandler(
      backgroundSync,
      (call) async => switch (call.method) {
        'isIgnoringBatteryOptimizations' => false,
        'hasAutostartSettings' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(backgroundSync, null);
  });

  Future<List<OnboardingStep>> stepsOn(
    PlatformCapabilities capabilities, {
    Map<String, Object> prefs = const {
      'onboarding.shown.$_userId': ['confirmPeople'],
    },
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        matrixClientProvider.overrideWithValue(
          buildTestClient(userId: _userId),
        ),
        accountSecurityFactsProvider.overrideWith(
          (ref) => Stream.value(_settled),
        ),
        platformCapabilitiesProvider.overrideWithValue(capabilities),
      ],
    );
    addTearDown(container.dispose);
    container.listen(onboardingStepsProvider, (_, _) {});
    return container.read(onboardingStepsProvider.future);
  }

  test('an account that never saw it learns to confirm people first', () async {
    expect(await stepsOn(iosCapabilities, prefs: const {}), [
      OnboardingStep.confirmPeople,
    ]);
  });

  test('Android asks how messages should arrive', () async {
    expect(await stepsOn(androidCapabilities), [OnboardingStep.deliveryMethod]);
  });

  test('iOS has one way for messages to arrive, so it asks nothing', () async {
    expect(await stepsOn(iosCapabilities), isEmpty);
  });

  group('once the method is chosen', () {
    const unifiedPushChosen = <String, Object>{
      'settings.notification_delivery_mode': 'unifiedPush',
      'onboarding.shown.$_userId': ['deliveryMethod', 'confirmPeople'],
    };

    test('Android asks for the battery exemption UnifiedPush needs', () async {
      expect(await stepsOn(androidCapabilities, prefs: unifiedPushChosen), [
        OnboardingStep.batteryExemption,
      ]);
    });

    test('a platform without a battery exemption never asks for one', () async {
      expect(
        await stepsOn(
          capabilitiesLike(androidCapabilities, batteryExemption: false),
          prefs: unifiedPushChosen,
        ),
        isEmpty,
      );
    });

    test(
      'iOS never asks, even with UnifiedPush left over in storage',
      () async {
        expect(
          await stepsOn(iosCapabilities, prefs: unifiedPushChosen),
          isEmpty,
        );
      },
    );
  });
}
