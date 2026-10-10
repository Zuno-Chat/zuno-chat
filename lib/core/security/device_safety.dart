import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';
import '../settings/app_preferences_provider.dart';

enum DeviceRisk { unlockedBootloader, rooted }

const _channel = MethodChannel('zuno/device_safety');
const _checkBudget = Duration(seconds: 5);
const _acknowledgedKey = 'security.device_warning_acknowledged';

Future<Set<DeviceRisk>> checkDeviceSafety({
  Duration budget = _checkBudget,
  PlatformCapabilities? capabilities,
}) async {
  final supported = (capabilities ?? ambientCapabilities).deviceSafetyChecks;
  if (!supported) return const {};
  try {
    final names = await _channel
        .invokeListMethod<String>('check')
        .timeout(budget);
    if (names == null) return const {};
    return {
      for (final risk in DeviceRisk.values)
        if (names.contains(risk.name)) risk,
    };
  } catch (error, stack) {
    reportCaught('device safety check', error, stack);
    return const {};
  }
}

final deviceRisksProvider = FutureProvider<Set<DeviceRisk>>(
  (ref) =>
      checkDeviceSafety(capabilities: ref.watch(platformCapabilitiesProvider)),
  retry: (_, _) => null,
);

final deviceWarningAcknowledgedProvider =
    NotifierProvider<DeviceWarningAcknowledgedNotifier, bool>(
      DeviceWarningAcknowledgedNotifier.new,
    );

class DeviceWarningAcknowledgedNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_acknowledgedKey) ?? false;

  Future<void> acknowledge() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_acknowledgedKey, true);
  }
}
