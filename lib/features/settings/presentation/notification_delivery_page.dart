import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/background_sync_service.dart';
import '../../../core/notifications/fcm_delivery_provider.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/notifications/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import '../../../core/push/unified_push_distributor_names.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'fcm_status_display.dart';
import 'push_target_status_page.dart';
import 'unified_push_status_display.dart';

const _statusSpinner = SizedBox(
  width: 24,
  height: 24,
  child: Padding(
    padding: EdgeInsets.all(2),
    child: CircularProgressIndicator(strokeWidth: 2),
  ),
);

class NotificationDeliveryPage extends ConsumerStatefulWidget {
  const NotificationDeliveryPage({super.key});

  @override
  ConsumerState<NotificationDeliveryPage> createState() =>
      _NotificationDeliveryPageState();
}

class _NotificationDeliveryPageState
    extends ConsumerState<NotificationDeliveryPage>
    with WidgetsBindingObserver {
  bool _ignoringBatteryOptimizations = false;
  bool _backgroundDataRestricted = false;
  String? _unifiedPushDistributor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBackgroundSyncPermissions();
    _refreshUnifiedPushStatus();
    unifiedPushDeliveryProvider.status.addListener(_onUnifiedPushStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(notificationDeliveryModeProvider) ==
          NotificationDeliveryMode.unifiedPush) {
        unawaited(unifiedPushDeliveryProvider.discoverDistributorsIfNeeded());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unifiedPushDeliveryProvider.status.removeListener(
      _onUnifiedPushStatusChanged,
    );
    super.dispose();
  }

  void _onUnifiedPushStatusChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshUnifiedPushStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBackgroundSyncPermissions();
      _refreshUnifiedPushStatus();
    }
  }

  Future<void> _refreshUnifiedPushStatus() async {
    final distributor = await unifiedPushDeliveryProvider.knownDistributor();
    if (!mounted) return;
    setState(() => _unifiedPushDistributor = distributor ?? '');
  }

  Future<void> _refreshBackgroundSyncPermissions() async {
    final ignoringBatteryOptimizations = await BackgroundSyncService.instance
        .isIgnoringBatteryOptimizations();
    final backgroundDataRestricted = await BackgroundSyncService.instance
        .isBackgroundDataRestricted();
    if (!mounted) return;
    setState(() {
      _ignoringBatteryOptimizations = ignoringBatteryOptimizations;
      _backgroundDataRestricted = backgroundDataRestricted;
    });
  }

  void _discoverDistributors() {
    unawaited(unifiedPushDeliveryProvider.discoverDistributors());
  }

  void _registerUnifiedPush() {
    final client = ref.read(matrixClientProvider);
    unawaited(unifiedPushDeliveryProvider.registerNow(client));
  }

  void _registerFcm() {
    final client = ref.read(matrixClientProvider);
    unawaited(fcmDeliveryProvider.registerNow(client));
  }

  void _openPushTargetStatus() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PushTargetStatusPage()));
  }

  Future<void> _chooseDeliveryMode(NotificationDeliveryMode current) async {
    final chosen = await showModalBottomSheet<NotificationDeliveryMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final mode in NotificationDeliveryMode.values)
              ListTile(
                leading: mode == current
                    ? const Icon(Icons.check_outlined)
                    : const SizedBox(width: 24),
                title: Text(mode.label),
                subtitle: Text(mode.description),
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;
    await ref.read(notificationDeliveryModeProvider.notifier).set(chosen);
    unawaited(kickOffDeliveryMode(ref.read(matrixClientProvider), chosen));
  }

  List<Widget> _deliveryModeSettings(NotificationDeliveryMode mode) {
    switch (mode) {
      case NotificationDeliveryMode.backgroundService:
        return [
          _batteryExemptionTile(mode),
          ListTile(
            leading: const Icon(Icons.wifi_tethering_outlined),
            title: const Text('Background data'),
            subtitle: Text(
              _backgroundDataRestricted
                  ? 'Data Saver stops background sync from using data while '
                        'the screen is off. Tap to allow it.'
                  : 'Background sync can use data even when the screen '
                        'is off',
            ),
            trailing: _backgroundDataRestricted
                ? const Icon(Icons.chevron_right)
                : const Icon(Icons.check_circle_outline),
            onTap: () =>
                BackgroundSyncService.instance.openBackgroundDataSettings(),
          ),
        ];
      case NotificationDeliveryMode.unifiedPush:
        final upStatus = unifiedPushDeliveryProvider.status.value;
        final busy = _unifiedPushStatusIsBusy(upStatus);
        final action = unifiedPushStatusAction(upStatus);
        return [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Distributor'),
            subtitle: Text(
              unifiedPushDistributorLabel(
                status: upStatus,
                distributor: _unifiedPushDistributor,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Look for a distributor',
              onPressed: busy ? null : _discoverDistributors,
            ),
          ),
          ListTile(
            leading: busy
                ? _statusSpinner
                : Icon(_unifiedPushStatusIcon(upStatus)),
            title: const Text('Status'),
            subtitle: Text(unifiedPushStatusLabel(upStatus)),
            onTap: action == UnifiedPushStatusAction.open
                ? _openPushTargetStatus
                : null,
            trailing: switch (action) {
              UnifiedPushStatusAction.none => null,
              UnifiedPushStatusAction.register => TextButton(
                onPressed: busy ? null : _registerUnifiedPush,
                child: const Text('Register'),
              ),
              UnifiedPushStatusAction.retry => TextButton(
                onPressed: busy ? null : _registerUnifiedPush,
                child: const Text('Retry'),
              ),
              UnifiedPushStatusAction.open => const Icon(Icons.chevron_right),
            },
          ),
          _batteryExemptionTile(mode),
          ValueListenableBuilder<bool>(
            valueListenable:
                unifiedPushDeliveryProvider.distributorBatteryRestricted,
            builder: (context, restricted, _) {
              final distributor = unifiedPushDeliveryProvider.savedDistributor;
              if (!restricted || distributor == null) {
                return const SizedBox.shrink();
              }
              return ListTile(
                leading: const Icon(Icons.battery_alert_outlined),
                title: Text(
                  '${unifiedPushDistributorDisplayName(distributor)} battery',
                ),
                subtitle: const Text(
                  'Set its battery use to Unrestricted so notifications reach '
                  'Zuno while the device sleeps',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    BackgroundSyncService.instance.openAppSettings(distributor),
              );
            },
          ),
        ];
      case NotificationDeliveryMode.fcm:
        return [
          ValueListenableBuilder<FcmStatus>(
            valueListenable: fcmDeliveryProvider.status,
            builder: (context, fcmStatus, _) {
              final busy = fcmStatusIsBusy(fcmStatus);
              final action = fcmStatusAction(fcmStatus);
              return ListTile(
                leading: busy
                    ? _statusSpinner
                    : Icon(_fcmStatusIcon(fcmStatus)),
                title: const Text('Status'),
                subtitle: Text(fcmStatusLabel(fcmStatus)),
                onTap: action == FcmStatusAction.open
                    ? _openPushTargetStatus
                    : null,
                trailing: switch (action) {
                  FcmStatusAction.none => null,
                  FcmStatusAction.register => TextButton(
                    onPressed: busy ? null : _registerFcm,
                    child: const Text('Register'),
                  ),
                  FcmStatusAction.retry => TextButton(
                    onPressed: busy ? null : _registerFcm,
                    child: const Text('Retry'),
                  ),
                  FcmStatusAction.open => const Icon(Icons.chevron_right),
                },
              );
            },
          ),
        ];
    }
  }

  Widget _batteryExemptionTile(NotificationDeliveryMode mode) {
    final forPush = mode == NotificationDeliveryMode.unifiedPush;
    final subtitle = switch ((_ignoringBatteryOptimizations, forPush)) {
      (true, true) =>
        'Android will not put Zuno to sleep, so notifications arrive while '
            'your device is locked',
      (true, false) => 'Android will not pause background sync to save power',
      (false, true) =>
        'Android puts Zuno to sleep after your device has been locked a while, '
            'and notifications stop arriving. Tap to allow.',
      (false, false) =>
        'Android may pause background sync to save power. Tap to let it run '
            'unrestricted.',
    };
    return ListTile(
      leading: const Icon(Icons.battery_charging_full_outlined),
      title: const Text('Unrestricted battery usage'),
      subtitle: Text(subtitle),
      trailing: _ignoringBatteryOptimizations
          ? const Icon(Icons.check_circle_outline)
          : const Icon(Icons.chevron_right),
      onTap: () =>
          BackgroundSyncService.instance.requestIgnoreBatteryOptimizations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deliveryMode = ref.watch(notificationDeliveryModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery')),
      body: CardListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 12, 28, 8),
            child: Text(
              'How messages and calls reach you while Zuno is closed. '
              'Background sync needs no setup. UnifiedPush needs a distributor '
              'app, such as ntfy, installed. Google services needs Google Play '
              'services.',
            ),
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Delivery method'),
                subtitle: Text(deliveryMode.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseDeliveryMode(deliveryMode),
              ),
              ..._deliveryModeSettings(deliveryMode),
            ],
          ),
        ],
      ),
    );
  }
}

bool _unifiedPushStatusIsBusy(UnifiedPushStatus status) {
  switch (status) {
    case UnifiedPushStatus.findingDistributor:
    case UnifiedPushStatus.registering:
    case UnifiedPushStatus.postingPusher:
      return true;
    case UnifiedPushStatus.idle:
    case UnifiedPushStatus.noDistributorFound:
    case UnifiedPushStatus.distributorSelected:
    case UnifiedPushStatus.ready:
    case UnifiedPushStatus.registrationFailed:
    case UnifiedPushStatus.pusherFailed:
      return false;
  }
}

IconData _fcmStatusIcon(FcmStatus status) {
  switch (status) {
    case FcmStatus.idle:
      return Icons.pause_circle_outline;
    case FcmStatus.checkingPlayServices:
    case FcmStatus.registering:
    case FcmStatus.postingPusher:
      return Icons.sync_outlined;
    case FcmStatus.playServicesUnavailable:
      return Icons.warning_amber_outlined;
    case FcmStatus.playServicesUpdateRequired:
      return Icons.system_update_outlined;
    case FcmStatus.ready:
      return Icons.check_circle_outline;
    case FcmStatus.tokenFailed:
    case FcmStatus.pusherFailed:
      return Icons.error_outline;
  }
}

IconData _unifiedPushStatusIcon(UnifiedPushStatus status) {
  switch (status) {
    case UnifiedPushStatus.idle:
      return Icons.pause_circle_outline;
    case UnifiedPushStatus.findingDistributor:
    case UnifiedPushStatus.registering:
    case UnifiedPushStatus.postingPusher:
      return Icons.sync_outlined;
    case UnifiedPushStatus.noDistributorFound:
      return Icons.warning_amber_outlined;
    case UnifiedPushStatus.distributorSelected:
      return Icons.arrow_circle_right_outlined;
    case UnifiedPushStatus.ready:
      return Icons.check_circle_outline;
    case UnifiedPushStatus.registrationFailed:
    case UnifiedPushStatus.pusherFailed:
      return Icons.error_outline;
  }
}
