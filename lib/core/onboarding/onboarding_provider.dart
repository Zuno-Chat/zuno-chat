import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/matrix_client_provider.dart';
import '../notifications/background_sync_service.dart';
import '../notifications/notification_delivery_mode.dart';
import '../notifications/notification_delivery_provider.dart';
import '../platform/platform_capabilities.dart';
import '../security/security_prompt.dart';
import '../security/security_prompt_provider.dart';
import '../security/security_providers.dart';
import '../settings/app_preferences_provider.dart';
import 'onboarding_step.dart';

String _shownKey(String userId) => 'onboarding.shown.$userId';

String _registeredKey(String userId) => 'onboarding.registered.$userId';

class OnboardingStore {
  final SharedPreferences _prefs;

  OnboardingStore(this._prefs);

  bool flowInProgress = false;

  final Map<String, Set<OnboardingStep>> _shownInMemory = {};

  Set<OnboardingStep> shown(String userId) {
    final stored = _prefs.getStringList(_shownKey(userId)) ?? const [];
    final byName = OnboardingStep.values.asNameMap();
    return {
      ...stored.map((name) => byName[name]).nonNulls,
      ...?_shownInMemory[userId],
    };
  }

  Future<void> markShown(String userId, OnboardingStep step) async {
    (_shownInMemory[userId] ??= <OnboardingStep>{}).add(step);
    final names = shown(userId).map((s) => s.name).toList();
    await _prefs.setStringList(_shownKey(userId), names);
  }

  bool justRegistered(String userId) =>
      _prefs.getBool(_registeredKey(userId)) ?? false;

  Future<void> markRegistered(String userId) =>
      _prefs.setBool(_registeredKey(userId), true);
}

final onboardingStoreProvider = Provider<OnboardingStore>((ref) {
  ref.watch(isLoggedInProvider);
  return OnboardingStore(ref.watch(sharedPreferencesProvider));
});

Future<bool> needsBatteryExemptionFor(
  NotificationDeliveryMode mode, {
  Future<bool> Function()? zunoIgnoresBatteryOptimizations,
  Future<bool> Function()? distributorBatteryRestricted,
  PlatformCapabilities? capabilities,
}) async {
  final supported = (capabilities ?? ambientCapabilities).batteryExemption;
  if (!supported) return false;
  if (!deliveryDependsOnBatteryExemption(mode)) return false;
  final zunoExempt =
      zunoIgnoresBatteryOptimizations ??
      BackgroundSyncService.instance.isIgnoringBatteryOptimizations;
  final distributorRestricted =
      distributorBatteryRestricted ?? _distributorBatteryRestricted;
  try {
    if (!await zunoExempt()) return true;
    if (mode != NotificationDeliveryMode.unifiedPush) return false;
    return await distributorRestricted();
  } catch (_) {
    return false;
  }
}

Future<bool> _distributorBatteryRestricted() async {
  await unifiedPushDeliveryProvider.refreshDistributorBattery();
  return unifiedPushDeliveryProvider.distributorBatteryRestricted.value;
}

Future<PermissionStatus?> _notificationPermission() async {
  try {
    return await Permission.notification.status;
  } catch (_) {
    return null;
  }
}

final onboardingStepsProvider = FutureProvider<List<OnboardingStep>>((
  ref,
) async {
  final client = ref.watch(matrixClientProvider);
  await ref.watch(firstSyncProvider.future);
  final userId = client.userID;
  if (userId == null) return const [];
  final facts = await ref.watch(accountSecurityFactsProvider.future);
  final store = ref.watch(onboardingStoreProvider);
  final lastPrompted = ref.watch(securityPromptStoreProvider).lastPrompted();
  final permission = await _notificationPermission();
  final capabilities = ref.watch(platformCapabilitiesProvider);
  return onboardingSteps(
    justRegistered: store.justRegistered(userId),
    notificationsAllowed: permission?.isGranted ?? false,
    canAskNotifications:
        permission != null &&
        !permission.isGranted &&
        !permission.isPermanentlyDenied,
    canChooseDelivery: capabilities.deliveryModes.length > 1,
    needsBatteryExemption: await needsBatteryExemptionFor(
      ref.watch(notificationDeliveryModeProvider),
      capabilities: capabilities,
    ),
    needsAutostart: await BackgroundSyncService.instance.hasAutostartSettings(),
    securityFacts: facts,
    hasConversations: client.rooms.any(
      (room) => room.membership == Membership.join && !room.isSpace,
    ),
    recoveryPromptOnCooldown:
        lastPrompted != null &&
        DateTime.now().difference(lastPrompted) < securityPromptCooldown,
    alreadyShown: store.shown(userId),
  );
});
