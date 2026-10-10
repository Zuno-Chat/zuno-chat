import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:zuno/core/notifications/notification_permission.dart';

void main() {
  group('notificationPermissionActionFor', () {
    for (final (name, turningOn, status, expected) in [
      (
        'turning on while denied requests the permission',
        true,
        PermissionStatus.denied,
        NotificationPermissionAction.request,
      ),
      (
        'turning on while already granted is a no-op',
        true,
        PermissionStatus.granted,
        NotificationPermissionAction.none,
      ),
      (
        'turning on while permanently denied opens settings, since the OS '
            'shows no prompt again',
        true,
        PermissionStatus.permanentlyDenied,
        NotificationPermissionAction.openSettings,
      ),
      (
        'turning off while granted opens settings, since the app cannot '
            'revoke an OS permission itself',
        false,
        PermissionStatus.granted,
        NotificationPermissionAction.openSettings,
      ),
      (
        'turning off while already denied still opens settings',
        false,
        PermissionStatus.denied,
        NotificationPermissionAction.openSettings,
      ),
    ]) {
      test(name, () {
        expect(
          notificationPermissionActionFor(
            turningOn: turningOn,
            currentStatus: status,
          ),
          expected,
        );
      });
    }
  });

  group('shouldRefreshBackgroundSync', () {
    for (final (name, previous, next, expected) in [
      (
        'true when moving from denied to granted',
        PermissionStatus.denied,
        PermissionStatus.granted,
        true,
      ),
      (
        'false when granted before and after',
        PermissionStatus.granted,
        PermissionStatus.granted,
        false,
      ),
      (
        'false when still denied after a declined request',
        PermissionStatus.denied,
        PermissionStatus.denied,
        false,
      ),
      (
        'false when moving away from granted',
        PermissionStatus.granted,
        PermissionStatus.denied,
        false,
      ),
    ]) {
      test(name, () {
        expect(
          shouldRefreshBackgroundSync(
            previousStatus: previous,
            newStatus: next,
          ),
          expected,
        );
      });
    }
  });
}
