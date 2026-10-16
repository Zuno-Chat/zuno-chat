import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/platform/background_restrictions.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/delivery/notification_delivery.dart';
import '../../../core/push/delivery/notification_delivery_mode.dart';
import '../../../core/push/fcm/fcm_availability_provider.dart';
import '../../../core/push/fcm/fcm_delivery_provider.dart';
import '../../../core/push/fcm/fcm_status_display.dart';
import '../../../core/push/unified_push/unified_push_delivery_provider.dart'
    show UnifiedPushStatus, unifiedPushDeliveryProvider;
import '../../../core/push/unified_push/unified_push_distributor_names.dart';
import '../../../core/push/unified_push/unified_push_status_display.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/sheet.dart';

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
  bool _hasAutostartSettings = false;
  String? _unifiedPushDistributor;
  late final _unifiedPushChanges = Listenable.merge([
    unifiedPushDeliveryProvider.status,
    unifiedPushDeliveryProvider.removed,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBackgroundSyncPermissions();
    _refreshUnifiedPushStatus();
    _checkAutostartSettings();
    _unifiedPushChanges.addListener(_onUnifiedPushStatusChanged);
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
    _unifiedPushChanges.removeListener(_onUnifiedPushStatusChanged);
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
    final offered = ref
        .read(platformCapabilitiesProvider)
        .deliveryModes
        .contains(NotificationDeliveryMode.unifiedPush);
    if (!offered) return;
    final distributor = await unifiedPushDeliveryProvider.knownDistributor();
    if (!mounted) return;
    setState(() => _unifiedPushDistributor = distributor ?? '');
  }

  Future<void> _refreshBackgroundSyncPermissions() async {
    final ignoringBatteryOptimizations = await BackgroundRestrictions.instance
        .isIgnoringBatteryOptimizations();
    final backgroundDataRestricted = await BackgroundRestrictions.instance
        .isBackgroundDataRestricted();
    if (!mounted) return;
    setState(() {
      _ignoringBatteryOptimizations = ignoringBatteryOptimizations;
      _backgroundDataRestricted = backgroundDataRestricted;
    });
  }

  Future<void> _checkAutostartSettings() async {
    final available = await BackgroundRestrictions.instance
        .hasAutostartSettings();
    if (mounted) setState(() => _hasAutostartSettings = available);
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

  void _fixFcm() {
    final client = ref.read(matrixClientProvider);
    unawaited(fcmDeliveryProvider.fixPlayServices(client));
  }

  Future<void> _chooseDeliveryMode(NotificationDeliveryMode current) async {
    final chosen = await showSheet<NotificationDeliveryMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final l10n = context.l10n;
            final fcm = ref.watch(fcmAvailabilityProvider).value;
            return Wrap(
              children: [
                for (final mode
                    in ref.watch(platformCapabilitiesProvider).deliveryModes)
                  if (deliveryModeChoice(l10n, mode, fcm: fcm) case (
                    :final enabled,
                    :final subtitle,
                  ))
                    ListTile(
                      enabled: enabled,
                      leading: mode == current
                          ? const Icon(Icons.check_outlined)
                          : const SizedBox(width: 24),
                      title: Text(mode.label(l10n)),
                      subtitle: Text(subtitle),
                      onTap: () => Navigator.of(context).pop(mode),
                    ),
              ],
            );
          },
        ),
      ),
    );
    if (chosen == null || chosen == current || !mounted) return;
    final client = ref.read(matrixClientProvider);
    final saved = await ref
        .read(notificationDeliveryModeProvider.notifier)
        .set(chosen);
    if (saved) unawaited(kickOffDeliveryMode(client, chosen));
  }

  List<Widget> _deliveryModeSettings(
    AppLocalizations l10n,
    NotificationDeliveryMode mode,
    PlatformCapabilities capabilities,
  ) {
    switch (mode) {
      case NotificationDeliveryMode.backgroundService:
        return [
          ..._batteryExemptionRows(l10n, mode, capabilities),
          if (capabilities.backgroundDataRestriction)
            ListTile(
              leading: const Icon(Icons.wifi_tethering_outlined),
              title: Text(l10n.diagnosticsLabelBackgroundData),
              subtitle: Text(
                _backgroundDataRestricted
                    ? l10n.notificationsBackgroundDataRestricted
                    : l10n.notificationsBackgroundDataAllowed,
              ),
              trailing: _backgroundDataRestricted
                  ? const Icon(Icons.chevron_right)
                  : const Icon(Icons.check_circle_outline),
              onTap: () =>
                  BackgroundRestrictions.instance.openBackgroundDataSettings(),
            ),
        ];
      case NotificationDeliveryMode.unifiedPush:
        final upStatus = unifiedPushDeliveryProvider.status.value;
        final busy = _unifiedPushStatusIsBusy(upStatus);
        final action = unifiedPushStatusAction(
          upStatus,
          removed: unifiedPushDeliveryProvider.removed.value,
        );
        return [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.pushTargetDistributor),
            subtitle: Text(
              unifiedPushDistributorLabel(
                l10n,
                status: upStatus,
                distributor: _unifiedPushDistributor,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.notificationsLookForDistributor,
              onPressed: busy ? null : _discoverDistributors,
            ),
          ),
          ListTile(
            leading: busy
                ? _statusSpinner
                : Icon(_unifiedPushStatusIcon(upStatus)),
            title: Text(l10n.commonStatus),
            subtitle: Text(unifiedPushStatusLabel(l10n, upStatus)),
            trailing: switch (action) {
              UnifiedPushStatusAction.none => null,
              UnifiedPushStatusAction.register => TextButton(
                onPressed: busy ? null : _registerUnifiedPush,
                child: Text(l10n.notificationsRegister),
              ),
              UnifiedPushStatusAction.retry => TextButton(
                onPressed: busy ? null : _registerUnifiedPush,
                child: Text(l10n.commonRetry),
              ),
            },
          ),
          ..._batteryExemptionRows(l10n, mode, capabilities),
          if (capabilities.batteryExemption)
            ValueListenableBuilder<bool>(
              valueListenable:
                  unifiedPushDeliveryProvider.distributorBatteryRestricted,
              builder: (context, restricted, _) {
                final distributor =
                    unifiedPushDeliveryProvider.savedDistributor;
                if (!restricted || distributor == null) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  leading: const Icon(Icons.battery_alert_outlined),
                  title: Text(
                    l10n.notificationsDistributorBattery(
                      unifiedPushDistributorDisplayName(distributor),
                    ),
                  ),
                  subtitle: Text(l10n.notificationsDistributorBatteryHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => BackgroundRestrictions.instance.openAppSettings(
                    distributor,
                  ),
                );
              },
            ),
        ];
      case NotificationDeliveryMode.fcm:
        return [
          ValueListenableBuilder<FcmStatus>(
            valueListenable: fcmDeliveryProvider.status,
            builder: (context, fcmStatus, _) {
              final fix = fcmFixLabel(l10n, fcmStatus);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fcmStatusRow(l10n, fcmStatus),
                  if (fix != null)
                    ListTile(
                      leading: Icon(
                        fcmStatus == FcmStatus.playServicesDisabled
                            ? Icons.toggle_on_outlined
                            : Icons.upgrade_outlined,
                      ),
                      title: Text(fix),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _fixFcm,
                    ),
                ],
              );
            },
          ),
          ..._batteryExemptionRows(l10n, mode, capabilities),
        ];
      case NotificationDeliveryMode.apns:
        return const [];
    }
  }

  Widget _fcmStatusRow(AppLocalizations l10n, FcmStatus status) {
    final busy = fcmStatusIsBusy(status);
    final action = fcmStatusAction(status);
    return ListTile(
      leading: busy ? _statusSpinner : Icon(_fcmStatusIcon(status)),
      title: Text(l10n.commonStatus),
      subtitle: Text(fcmStatusLabel(l10n, status)),
      trailing: switch (action) {
        PushStatusAction.none || PushStatusAction.fix => null,
        PushStatusAction.register => TextButton(
          onPressed: busy ? null : _registerFcm,
          child: Text(l10n.notificationsRegister),
        ),
        PushStatusAction.retry => TextButton(
          onPressed: busy ? null : _registerFcm,
          child: Text(l10n.commonRetry),
        ),
      },
    );
  }

  List<Widget> _batteryExemptionRows(
    AppLocalizations l10n,
    NotificationDeliveryMode mode,
    PlatformCapabilities capabilities,
  ) {
    if (!capabilities.batteryExemption) return const [];
    final subtitle = switch ((_ignoringBatteryOptimizations, mode)) {
      (true, NotificationDeliveryMode.unifiedPush) =>
        l10n.notificationsBatteryUnifiedPushOn,
      (true, NotificationDeliveryMode.fcm) => l10n.notificationsBatteryFcmOn,
      (true, NotificationDeliveryMode.backgroundService) =>
        l10n.notificationsBatteryBackgroundSyncOn,
      (false, NotificationDeliveryMode.unifiedPush) =>
        l10n.notificationsBatteryUnifiedPushOff,
      (false, NotificationDeliveryMode.fcm) => l10n.notificationsBatteryFcmOff,
      (false, NotificationDeliveryMode.backgroundService) =>
        l10n.notificationsBatteryBackgroundSyncOff,
      (_, NotificationDeliveryMode.apns) => null,
    };
    if (subtitle == null) return const [];
    return [
      ListTile(
        leading: const Icon(Icons.battery_charging_full_outlined),
        title: Text(l10n.notificationsUnrestrictedBattery),
        subtitle: Text(subtitle),
        trailing: _ignoringBatteryOptimizations
            ? const Icon(Icons.check_circle_outline)
            : const Icon(Icons.chevron_right),
        onTap: () =>
            BackgroundRestrictions.instance.requestIgnoreBatteryOptimizations(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deliveryMode = ref.watch(notificationDeliveryModeProvider);
    final capabilities = ref.watch(platformCapabilitiesProvider);
    ref.watch(fcmAvailabilityProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsDelivery)),
      body: CardListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
            child: Text(l10n.notificationsDeliveryIntro),
          ),
          CardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: Text(l10n.notificationsDeliveryMethod),
                subtitle: Text(deliveryMode.label(l10n)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _chooseDeliveryMode(deliveryMode),
              ),
              ..._deliveryModeSettings(l10n, deliveryMode, capabilities),
              if (_hasAutostartSettings)
                ListTile(
                  leading: const Icon(Icons.restart_alt_outlined),
                  title: Text(l10n.notificationsAutostart),
                  subtitle: Text(l10n.notificationsAutostartHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      BackgroundRestrictions.instance.openAutostartSettings(),
                ),
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
    case FcmStatus.playServicesDisabled:
    case FcmStatus.notConfigured:
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
