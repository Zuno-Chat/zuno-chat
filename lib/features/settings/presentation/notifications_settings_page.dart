import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/notifications/background_sync_service.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../../core/notifications/notification_permission_provider.dart';
import '../../../core/notifications/notify_me.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import 'notification_delivery_page.dart';

class NotificationsSettingsPage extends ConsumerStatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  ConsumerState<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState
    extends ConsumerState<NotificationsSettingsPage>
    with WidgetsBindingObserver {
  PermissionStatus _status = PermissionStatus.denied;

  bool _fullScreenIntentAllowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    _refreshFullScreenIntentStatus();
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
    }
  }

  Future<void> _refreshFullScreenIntentStatus() async {
    final allowed = await CallNotificationService.instance
        .canUseFullScreenIntent();
    if (mounted) setState(() => _fullScreenIntentAllowed = allowed);
  }

  Future<void> _refreshStatus() async {
    final previous = _status;
    final status = await Permission.notification.status;
    if (mounted) setState(() => _status = status);
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
        if (mounted) setState(() => _status = result);
        unawaited(ref.read(notificationsAllowedProvider.notifier).refresh());
        _maybeRefreshBackgroundSync(previous, result);
      case NotificationPermissionAction.openSettings:
        await openAppSettings();
      case NotificationPermissionAction.none:
        break;
    }
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
    final deliveryMode = ref.watch(notificationDeliveryModeProvider);
    final notifyMe = ref.watch(notifyMeProvider);
    final ringtone = ref.watch(ringtoneEnabledProvider);
    final callVibration = ref.watch(callVibrationEnabledProvider);
    final messageTone = ref.watch(messageToneEnabledProvider);
    final messageVibration = ref.watch(messageVibrationEnabledProvider);
    final notificationsEnabled = _status.isGranted;
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
                      ? 'Calls can ring full screen, and background sync shows '
                            'its status in the notification shade'
                      : 'Off. This device is not registered for notifications, '
                            'so nothing is delivered to it.',
                ),
                value: notificationsEnabled,
                onChanged: _onToggle,
              ),
              ListTile(
                leading: const Icon(Icons.phone_in_talk_outlined),
                title: const Text('Full-screen call alerts'),
                subtitle: Text(
                  _fullScreenIntentAllowed
                      ? 'A call takes over the screen while the device is '
                            'locked'
                      : 'Off. Calls show only as a regular notification, even '
                            'while locked. Tap to allow.',
                ),
                trailing: _fullScreenIntentAllowed
                    ? const Icon(Icons.check_circle_outline)
                    : const Icon(Icons.chevron_right),
                onTap: () => CallNotificationService.instance
                    .openFullScreenIntentSettings(),
              ),
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
                      value: NotifyMe.mentionsOnly,
                    ),
                  ],
                ),
              ),
            ],
          ),
          CardGroup(
            title: 'Sounds & vibration',
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
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibrate for calls'),
                subtitle: const Text('Buzz while a call is ringing'),
                value: callVibration,
                onChanged: (value) =>
                    ref.read(callVibrationEnabledProvider.notifier).set(value),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Message tone'),
                subtitle: const Text('Play a sound for new messages'),
                value: messageTone,
                onChanged: (value) =>
                    ref.read(messageToneEnabledProvider.notifier).set(value),
              ),
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
              "notification volume, and stay silent when it is on silent.",
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
