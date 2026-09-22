import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:zuno/core/notifications/notification_permission.dart';

void main() {
  group('notificationPermissionActionFor', () {
    test('turning on while denied requests the permission', () {
      expect(
        notificationPermissionActionFor(
          turningOn: true,
          currentStatus: PermissionStatus.denied,
        ),
        NotificationPermissionAction.request,
      );
    });

    test('turning on while already granted is a no-op', () {
      expect(
        notificationPermissionActionFor(
          turningOn: true,
          currentStatus: PermissionStatus.granted,
        ),
        NotificationPermissionAction.none,
      );
    });

    test('turning on while permanently denied opens settings instead of '
        're-requesting (the OS won\'t show its own prompt again)', () {
      expect(
        notificationPermissionActionFor(
          turningOn: true,
          currentStatus: PermissionStatus.permanentlyDenied,
        ),
        NotificationPermissionAction.openSettings,
      );
    });

    test('turning off while granted opens settings — this app can\'t revoke '
        'an OS permission itself', () {
      expect(
        notificationPermissionActionFor(
          turningOn: false,
          currentStatus: PermissionStatus.granted,
        ),
        NotificationPermissionAction.openSettings,
      );
    });

    test('turning off while already denied still opens settings', () {
      expect(
        notificationPermissionActionFor(
          turningOn: false,
          currentStatus: PermissionStatus.denied,
        ),
        NotificationPermissionAction.openSettings,
      );
    });
  });

  group('shouldRefreshBackgroundSync', () {
    test('true when transitioning from denied to granted', () {
      expect(
        shouldRefreshBackgroundSync(
          previousStatus: PermissionStatus.denied,
          newStatus: PermissionStatus.granted,
        ),
        isTrue,
      );
    });

    test('false when already granted before and after (no real change)', () {
      expect(
        shouldRefreshBackgroundSync(
          previousStatus: PermissionStatus.granted,
          newStatus: PermissionStatus.granted,
        ),
        isFalse,
      );
    });

    test('false when still denied after (request was declined)', () {
      expect(
        shouldRefreshBackgroundSync(
          previousStatus: PermissionStatus.denied,
          newStatus: PermissionStatus.denied,
        ),
        isFalse,
      );
    });

    test('false when transitioning away from granted', () {
      expect(
        shouldRefreshBackgroundSync(
          previousStatus: PermissionStatus.granted,
          newStatus: PermissionStatus.denied,
        ),
        isFalse,
      );
    });
  });
}
