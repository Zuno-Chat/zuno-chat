import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/apns_delivery_provider.dart';
import '../../../core/notifications/background_sync_service.dart';
import '../../../core/notifications/delivery_failure.dart';
import '../../../core/notifications/delivery_failure_provider.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../../core/notifications/notification_permission_provider.dart';
import '../../../core/notifications/notification_preview.dart';
import '../../../core/notifications/notify_me.dart';
import '../../../core/platform/platform_capabilities.dart';
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
      (false, _) =>
        'New messages show on this device, even while Zuno is closed',
      (true, NotificationDeliveryMode.backgroundService) =>
        'Calls can ring full screen, and background sync shows its status in '
            'the notification shade',
      (true, _) => 'Calls can ring full screen',
    };
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: CardListView(
        children: [
          CardGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Enable notifications'),
                subtitle: Text(
                  notificationsEnabled
                      ? enabledSubtitle
                      : 'Off. This device is not registered for notifications, '
                            'so nothing is delivered to it.',
                ),
                value: notificationsEnabled,
                onChanged: _onToggle,
              ),
              if (notificationsEnabled)
                for (final channel in _silencedChannels)
                  ListTile(
                    leading: const Icon(Icons.notifications_off_outlined),
                    title: Text('${channel.name} are silenced'),
                    subtitle: const Text(
                      'Android shows them without a sound, or not at all. '
                      'Tap to change.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => CallNotificationService.instance
                        .openChannelSettings(channel.id),
                  ),
              if (notificationsEnabled) ...[
                if (capabilities.fullScreenIntent)
                  ListTile(
                    leading: const Icon(Icons.phone_in_talk_outlined),
                    title: const Text('Full-screen call alerts'),
                    subtitle: Text(
                      _fullScreenIntentAllowed
                          ? 'A call takes over the screen while the device is '
                                'locked'
                          : 'Off. Calls show only as a regular notification, '
                                'even while locked. Tap to allow.',
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
                    title: const Text('Delivery'),
                    subtitle: Text(deliveryMode.label),
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
                    title: Text(deliveryFailure.message),
                    trailing: TextButton(
                      onPressed: () => runDeliveryFailureAction(
                        context,
                        ref,
                        deliveryFailure,
                      ),
                      child: Text(
                        deliveryFailureActionLabel(deliveryFailure.action),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          CardGroup(
            title: 'Notifications for',
            children: [
              RadioGroup<NotifyMe>(
                groupValue: notifyMe,
                onChanged: (mode) =>
                    ref.read(notifyMeProvider.notifier).set(mode!),
                child: const Column(
                  children: [
                    RadioListTile<NotifyMe>(
                      title: Text('All messages'),
                      value: NotifyMe.all,
                    ),
                    RadioListTile<NotifyMe>(
                      title: Text('Mentions only'),
                      subtitle: Text('Other messages show silently'),
                      value: NotifyMe.mentionsOnly,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (capabilities.nseNotifications) ...[
            CardGroup(
              title: 'Notification content',
              children: [
                RadioGroup<NotificationPreview>(
                  groupValue: preview,
                  onChanged: (level) => _setPreview(level!),
                  child: Column(
                    children: [
                      for (final level in NotificationPreview.values)
                        RadioListTile<NotificationPreview>(
                          title: Text(level.label),
                          subtitle: Text(level.description),
                          value: level,
                        ),
                    ],
                  ),
                ),
                if (_previewHintDue(preview))
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text(
                      'This iOS version can keep notification text after it '
                      'is deleted',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Name only keeps message text out of notifications.',
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _setPreview(NotificationPreview.nameOnly),
                              child: const Text('Use Name only'),
                            ),
                            TextButton(
                              onPressed: _finishPreviewHint,
                              child: const Text('Keep as is'),
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
                'This device keeps a copy of what notifications show. With '
                'Name only or Nothing, message text stays in Zuno. Incoming '
                'calls follow this setting too.',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          CardGroup(
            title: capabilities.vibrationPatterns
                ? 'Sounds & vibration'
                : 'Sounds',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.music_note_outlined),
                title: const Text('Ringtone'),
                subtitle: const Text(
                  'Play a ringtone for incoming calls, and a ringing tone '
                  'while you wait for someone to answer',
                ),
                value: ringtone,
                onChanged: (value) =>
                    ref.read(ringtoneEnabledProvider.notifier).set(value),
              ),
              if (capabilities.vibrationPatterns)
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Vibrate for calls'),
                  subtitle: const Text('Buzz while a call is ringing'),
                  value: callVibration,
                  onChanged: (value) => ref
                      .read(callVibrationEnabledProvider.notifier)
                      .set(value),
                ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Message tone'),
                subtitle: const Text('Play a sound for new messages'),
                value: messageTone,
                onChanged: _setMessageTone,
              ),
              if (capabilities.vibrationPatterns)
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Vibrate for messages'),
                  subtitle: const Text('Buzz once for a new message'),
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
              "Ringing and message tones follow your device's ring and "
              'notification volume, and stay silent when it is on silent.',
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
                  title: const Text('Diagnostics'),
                  subtitle: const Text(
                    'Check how notifications and calls reach this device',
                  ),
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
