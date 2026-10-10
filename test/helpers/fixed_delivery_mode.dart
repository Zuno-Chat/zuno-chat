import 'package:flutter_riverpod/misc.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

class FixedDeliveryModeNotifier extends NotificationDeliveryModeNotifier {
  FixedDeliveryModeNotifier(this._mode);
  final NotificationDeliveryMode _mode;

  @override
  NotificationDeliveryMode build() => _mode;

  void switchTo(NotificationDeliveryMode mode) => state = mode;
}

Override fixedDeliveryMode(NotificationDeliveryMode mode) =>
    notificationDeliveryModeProvider.overrideWith(
      () => FixedDeliveryModeNotifier(mode),
    );
