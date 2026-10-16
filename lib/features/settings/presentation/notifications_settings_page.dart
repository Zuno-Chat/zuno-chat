import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/settings/notification_permission.dart';
import '../../../core/notifications/settings/notification_preview.dart';
import '../../../core/notifications/settings/notifications_allowed_provider.dart';
import '../../../core/notifications/settings/notify_me.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/push/apns/apns_delivery_provider.dart';
import '../../../core/push/background_sync/background_sync_service.dart';
import '../../../core/push/delivery/delivery_failure.dart';
import '../../../core/push/delivery/delivery_failure_provider.dart';
import '../../../core/push/delivery/notification_delivery_mode.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'delivery_failure_action.dart';
import 'notification_delivery_page.dart';
import 'push_diagnostics_page.dart';

class NotificationsSettingsPage extends ConsumerStatefulWidget {
  const NotificationsSettingsPage({super.key, this.osVersion});

  final String? osVersion;

  @override
  ConsumerState<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState
    extends ConsumerState<NotificationsSettingsPage>
    with WidgetsBindingObserver {
  PermissionStatus _status = PermissionStatus.denied;

  bool _fullScreenIntentAllowed = true;

  List<SilencedChannel> _silencedChannels = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _refreshFullScreenIntentStatus();
    _refreshSilencedChannels();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      _refreshFullScreenIntentStatus();
      _refreshSilencedChannels();
    }
  }

  Future<void> _refreshSilencedChannels() async {
    final silenced = await CallNotificationService.instance.silencedChannels();
    if (mounted) setState(() => _silencedChannels = silenced);
  }

  Future<void> _refreshFullScreenIntentStatus() async {
    final allowed = await CallNotificationService.instance
        .canUseFullScreenIntent();
    if (mounted) setState(() => _fullScreenIntentAllowed = allowed);
  }

  Future<void> _refreshStatus() async {
    final previous = _status;
    final status = await Permission.notification.status;
    if (!mounted) return;
    setState(() => _status = status);
    unawaited(ref.read(notificationsAllowedProvider.notifier).refresh());
    _maybeRefreshBackgroundSync(previous, status);
  }

  Future<void> _onToggle(bool turningOn) async {
    switch (notificationPermissionActionFor(
      turningOn: turningOn,
      currentStatus: _status,
    )) {
      case NotificationPermissionAction.request:
        final previous = _status;
        final result = await Permission.notification.request();
        if (!mounted) return;
        setState(() => _status = result);
        unawaited(ref.read(notificationsAllowedProvider.notifier).refresh());
        _maybeRefreshBackgroundSync(previous, result);
      case NotificationPermissionAction.openSettings:
        await CallNotificationService.instance.openNotificationSettings();
      case NotificationPermissionAction.none:
        break;
    }
  }

  Future<void> _setPreview(NotificationPreview level) async {
    await ref.read(notificationPreviewProvider.notifier).set(level);
    await _finishPreviewHint();
  }

  Future<void> _finishPreviewHint() async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(notificationPreviewHintKey, true);
    if (mounted) setState(() {});
  }

  bool _previewHintDue(NotificationPreview preview) {
    final prefs = ref.read(sharedPreferencesProvider);
    return preview == NotificationPreview.full &&
        prefs.getBool(notificationPreviewHintKey) != true &&
        notificationRetentionUnpatched(
          widget.osVersion ?? Platform.operatingSystemVersion,
        );
  }

  Future<void> _setMessageTone(bool on) async {
    final applePush = ref.read(platformCapabilitiesProvider).apnsRegistration;
    final client = applePush ? ref.read(matrixClientProvider) : null;
    await ref.read(messageToneEnabledProvider.notifier).set(on);
    if (client != null) await apnsDeliveryProvider.messageToneChanged(client);
  }

  void _maybeRefreshBackgroundSync(
    PermissionStatus previous,
    PermissionStatus current,
  ) {
    if (ref.read(notificationDeliveryModeProvider) !=
        NotificationDeliveryMode.backgroundService) {
      return;
    }
    if (shouldRefreshBackgroundSync(
      previousStatus: previous,
      newStatus: current,
    )) {
      BackgroundSyncService.instance.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final canChooseDelivery = capabilities.deliveryModes.length > 1;
    final deliveryMode = ref.watch(notificationDeliveryModeProvider);
    final notifyMe = ref.watch(notifyMeProvider);
    final preview = ref.watch(notificationPreviewProvider);
    final ringtone = ref.watch(ringtoneEnabledProvider);
    final callVibration = ref.watch(callVibrationEnabledProvider);
    final messageTone = ref.watch(messageToneEnabledProvider);
    final messageVibration = ref.watch(messageVibrationEnabledProvider);
    final notificationsEnabled = _status.isGranted;
    final deliveryFailure = notificationsEnabled && !canChooseDelivery
        ? ref.watch(deliveryFailureProvider)
        : null;
    final enabledSubtitle = switch ((
      capabilities.fullScreenIntent,
      deliveryMode,
    )) {
      (false, _) => l10n.notificationsEnabledMessagesOnly,
      (true, NotificationDeliveryMode.backgroundService) =>
        l10n.notificationsEnabledWithBackgroundSync,
      (true, _) => l10n.notificationsEnabledCallsFullScreen,
    };
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: CardListView(
        children: [
          CardGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: Text(l10n.notificationsEnable),
                subtitle: Text(
                  notificationsEnabled
                      ? enabledSubtitle
                      : l10n.notificationsOffNotRegistered,
                ),
                value: notificationsEnabled,
                onChanged: _onToggle,
              ),
              if (notificationsEnabled)
                for (final channel in _silencedChannels)
                  ListTile(
                    leading: const Icon(Icons.notifications_off_outlined),
                    title: Text(
                      l10n.notificationsChannelSilenced(channel.name),
                    ),
                    subtitle: Text(l10n.notificationsChannelSilencedHint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => CallNotificationService.instance
                        .openChannelSettings(channel.id),
                  ),
              if (notificationsEnabled) ...[
                if (capabilities.fullScreenIntent)
                  ListTile(
                    leading: const Icon(Icons.phone_in_talk_outlined),
                    title: Text(l10n.diagnosticsLabelFullScreenCallAlerts),
                    subtitle: Text(
                      _fullScreenIntentAllowed
                          ? l10n.notificationsFullScreenOn
                          : l10n.notificationsFullScreenOff,
                    ),
                    trailing: _fullScreenIntentAllowed
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.chevron_right),
                    onTap: () => CallNotificationService.instance
                        .openFullScreenIntentSettings(),
                  ),
                if (canChooseDelivery)
                  ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined),
                    title: Text(l10n.notificationsDelivery),
                    subtitle: Text(deliveryMode.label(l10n)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationDeliveryPage(),
                      ),
                    ),
                  ),
                if (deliveryFailure != null)
                  ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(deliveryFailure.message(l10n)),
                    trailing: TextButton(
                      onPressed: () => runDeliveryFailureAction(
                        context,
                        ref,
                        deliveryFailure,
                      ),
                      child: Text(
                        deliveryFailureActionLabel(
                          l10n,
                          deliveryFailure.action,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          CardGroup(
            title: l10n.notificationsFor,
            children: [
              RadioGroup<NotifyMe>(
                groupValue: notifyMe,
                onChanged: (mode) =>
                    ref.read(notifyMeProvider.notifier).set(mode!),
                child: Column(
                  children: [
                    RadioListTile<NotifyMe>(
                      title: Text(l10n.notificationsAllMessages),
                      value: NotifyMe.all,
                    ),
                    RadioListTile<NotifyMe>(
                      title: Text(l10n.notificationsMentionsOnly),
                      subtitle: Text(l10n.notificationsMentionsOnlyHint),
                      value: NotifyMe.mentionsOnly,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (capabilities.nseNotifications) ...[
            CardGroup(
              title: l10n.notificationsContent,
              children: [
                RadioGroup<NotificationPreview>(
                  groupValue: preview,
                  onChanged: (level) => _setPreview(level!),
                  child: Column(
                    children: [
                      for (final level in NotificationPreview.values)
                        RadioListTile<NotificationPreview>(
                          title: Text(level.label(l10n)),
                          subtitle: Text(level.description(l10n)),
                          value: level,
                        ),
                    ],
                  ),
                ),
                if (_previewHintDue(preview))
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(l10n.notificationsRetentionTitle),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.notificationsRetentionHint),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _setPreview(NotificationPreview.nameOnly),
                              child: Text(l10n.notificationsUseNameOnly),
                            ),
                            TextButton(
                              onPressed: _finishPreviewHint,
                              child: Text(l10n.notificationsKeepAsIs),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 8),
              child: Text(
                l10n.notificationsContentFootnote,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          CardGroup(
            title: capabilities.vibrationPatterns
                ? l10n.notificationsSoundsAndVibration
                : l10n.notificationsSounds,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.music_note_outlined),
                title: Text(l10n.notificationsRingtone),
                subtitle: Text(l10n.notificationsRingtoneHint),
                value: ringtone,
                onChanged: (value) =>
                    ref.read(ringtoneEnabledProvider.notifier).set(value),
              ),
              if (capabilities.vibrationPatterns)
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: Text(l10n.notificationsVibrateCalls),
                  subtitle: Text(l10n.notificationsVibrateCallsHint),
                  value: callVibration,
                  onChanged: (value) => ref
                      .read(callVibrationEnabledProvider.notifier)
                      .set(value),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: Text(l10n.notificationsMessageTone),
                subtitle: Text(l10n.notificationsMessageToneHint),
                value: messageTone,
                onChanged: _setMessageTone,
              ),
              if (capabilities.vibrationPatterns)
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: Text(l10n.notificationsVibrateMessages),
                  subtitle: Text(l10n.notificationsVibrateMessagesHint),
                  value: messageVibration,
                  onChanged: (value) => ref
                      .read(messageVibrationEnabledProvider.notifier)
                      .set(value),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 6, 28, 8),
            child: Text(
              l10n.notificationsVolumeFootnote,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (capabilities.pushDiagnostics)
            CardGroup(
              children: [
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(l10n.diagnosticsTitle),
                  subtitle: Text(l10n.notificationsDiagnosticsHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PushDiagnosticsPage(),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
