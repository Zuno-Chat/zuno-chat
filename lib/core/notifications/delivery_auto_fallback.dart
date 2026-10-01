import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unifiedpush/unifiedpush.dart';

import '../settings/app_preferences_provider.dart';
import 'fcm_delivery_provider.dart';
import 'notification_delivery_mode.dart';

NotificationDeliveryMode? autoFallbackFor({
  required FcmStatus fcm,
  required bool fcmRegistered,
  required bool userChoseMode,
  required bool hasDistributor,
}) {
  if (userChoseMode || fcmRegistered || !_fallbackStatuses.contains(fcm)) {
    return null;
  }
  return hasDistributor
      ? NotificationDeliveryMode.unifiedPush
      : NotificationDeliveryMode.backgroundService;
}

const _fallbackStatuses = {
  FcmStatus.playServicesUnavailable,
  FcmStatus.playServicesDisabled,
  FcmStatus.notConfigured,
};

final autoSelectedDeliveryModeProvider =
    NotifierProvider<
      AutoSelectedDeliveryModeNotifier,
      NotificationDeliveryMode?
    >(AutoSelectedDeliveryModeNotifier.new);

class AutoSelectedDeliveryModeNotifier
    extends Notifier<NotificationDeliveryMode?> {
  @override
  NotificationDeliveryMode? build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(notificationDeliveryModeAutoKey);
    return NotificationDeliveryMode.values.asNameMap()[stored];
  }

  void refresh() => state = build();

  Future<void> acknowledge() async {
    state = null;
    await ref
        .read(sharedPreferencesProvider)
        .remove(notificationDeliveryModeAutoKey);
  }
}

final deliveryAutoFallbackProvider =
    NotifierProvider<DeliveryAutoFallbackNotifier, void>(
      DeliveryAutoFallbackNotifier.new,
    );

class DeliveryAutoFallbackNotifier extends Notifier<void> {
  bool _switching = false;

  @override
  void build() {
    void onStatus() => unawaited(_maybeSwitch());
    fcmDeliveryProvider.status.addListener(onStatus);
    ref.onDispose(() => fcmDeliveryProvider.status.removeListener(onStatus));
    unawaited(_maybeSwitch());
  }

  Future<void> _maybeSwitch() async {
    if (_switching) return;
    final modes = ref.read(notificationDeliveryModeProvider.notifier);
    if (ref.read(notificationDeliveryModeProvider) !=
        NotificationDeliveryMode.fcm) {
      return;
    }
    final status = fcmDeliveryProvider.status.value;
    if (!_fallbackStatuses.contains(status) ||
        modes.userChose ||
        fcmDeliveryProvider.registered) {
      return;
    }
    _switching = true;
    try {
      final distributors = await UnifiedPush.getDistributors();
      final target = autoFallbackFor(
        fcm: fcmDeliveryProvider.status.value,
        fcmRegistered: fcmDeliveryProvider.registered,
        userChoseMode: modes.userChose,
        hasDistributor: distributors.isNotEmpty,
      );
      if (target == null) return;
      debugPrint('zuno/push: no Google services, switching to ${target.name}');
      await modes.autoSelect(target);
      ref.read(autoSelectedDeliveryModeProvider.notifier).refresh();
    } catch (e) {
      debugPrint('zuno/push: automatic transport fallback failed ($e)');
    } finally {
      _switching = false;
    }
  }
}
