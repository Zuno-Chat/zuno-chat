import 'package:permission_handler/permission_handler.dart';

enum NotificationPermissionAction {
  request,
  openSettings,
  none,
}

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
