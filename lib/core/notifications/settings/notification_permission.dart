import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../errors/caught_errors.dart';
import '../../push/background_sync/background_sync_service.dart';
import '../../push/delivery/notification_delivery_mode.dart';
import '../../settings/app_preferences_provider.dart';
import 'notifications_allowed_provider.dart';

enum NotificationPermissionAction { request, openSettings, none }

NotificationPermissionAction notificationPermissionActionFor({
  required bool turningOn,
  required PermissionStatus currentStatus,
}) {
  if (!turningOn) return NotificationPermissionAction.openSettings;
  if (currentStatus.isGranted) return NotificationPermissionAction.none;
  if (currentStatus.isPermanentlyDenied) {
    return NotificationPermissionAction.openSettings;
  }
  return NotificationPermissionAction.request;
}

bool shouldRefreshBackgroundSync({
  required PermissionStatus previousStatus,
  required PermissionStatus newStatus,
}) => !previousStatus.isGranted && newStatus.isGranted;

Future<void> notificationPermissionChanged(
  WidgetRef ref, {
  required PermissionStatus previous,
  required PermissionStatus current,
}) async {
  final restartBackgroundSync =
      ref.read(notificationDeliveryModeProvider) ==
          NotificationDeliveryMode.backgroundService &&
      shouldRefreshBackgroundSync(previousStatus: previous, newStatus: current);
  final refreshed = ref.read(notificationsAllowedProvider.notifier).refresh();
  if (restartBackgroundSync) {
    unawaited(BackgroundSyncService.instance.start());
  }
  await refreshed;
}

Future<bool> mayRegisterForNotifications() async {
  try {
    return (await Permission.notification.status).isGranted;
  } catch (e, s) {
    reportCaught('notification permission check', e, s);
    return true;
  }
}
