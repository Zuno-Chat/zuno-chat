import 'package:flutter_riverpod/misc.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';

class FixedNotificationsAllowedNotifier extends NotificationsAllowedNotifier {
  FixedNotificationsAllowedNotifier(this._initial);

  final bool? _initial;
  int refreshes = 0;

  @override
  bool? build() => _initial;

  @override
  Future<bool?> refresh() async {
    refreshes++;
    return state;
  }

  void set(bool allowed) => state = allowed;
}

Override fixedNotificationsAllowed(bool? allowed) =>
    notificationsAllowedProvider.overrideWith(
      () => FixedNotificationsAllowedNotifier(allowed),
    );
