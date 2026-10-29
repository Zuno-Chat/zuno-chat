import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zuno/core/notifications/settings/notification_permission.dart';
import 'package:zuno/core/notifications/settings/notifications_allowed_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/delivery/notification_delivery_mode.dart';

import '../../../helpers/fake_permissions.dart';
import '../../../helpers/fixed_delivery_mode.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/preferences_container.dart';

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

  group('notificationPermissionChanged', () {
    late RecordedMethodCalls backgroundSync;
    late FakePermissions permissions;

    setUp(() {
      ambientCapabilities = androidCapabilities;
      backgroundSync = recordMethodChannel('zuno/background_sync');
      permissions = installFakePermissions();
    });

    Future<({WidgetRef ref, ProviderContainer container})> refOn(
      WidgetTester tester,
      NotificationDeliveryMode mode,
    ) async {
      final container = await containerWithPreferences(
        {},
        overrides: [fixedDeliveryMode(mode)],
      );
      late WidgetRef captured;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      );
      container.read(notificationsAllowedProvider);
      await tester.pump();
      return (ref: captured, container: container);
    }

    testWidgets('granted under background sync restarts it and tells the '
        'app notifications are allowed', (tester) async {
      permissions.onCheck = permissionDenied;
      final (:ref, :container) = await refOn(
        tester,
        NotificationDeliveryMode.backgroundService,
      );
      permissions.onCheck = permissionGranted;

      await notificationPermissionChanged(
        ref,
        previous: PermissionStatus.denied,
        current: PermissionStatus.granted,
      );

      expect(backgroundSync.methods, ['startBackgroundSyncService']);
      expect(container.read(notificationsAllowedProvider), isTrue);
    });

    testWidgets('granted under push delivery leaves background sync alone', (
      tester,
    ) async {
      final (:ref, container: _) = await refOn(
        tester,
        NotificationDeliveryMode.fcm,
      );

      await notificationPermissionChanged(
        ref,
        previous: PermissionStatus.denied,
        current: PermissionStatus.granted,
      );

      expect(backgroundSync.methods, isEmpty);
    });

    testWidgets('still denied restarts nothing but checks again', (
      tester,
    ) async {
      final (:ref, :container) = await refOn(
        tester,
        NotificationDeliveryMode.backgroundService,
      );
      permissions.onCheck = permissionDenied;

      await notificationPermissionChanged(
        ref,
        previous: PermissionStatus.denied,
        current: PermissionStatus.denied,
      );

      expect(backgroundSync.methods, isEmpty);
      expect(container.read(notificationsAllowedProvider), isFalse);
    });
  });
}
