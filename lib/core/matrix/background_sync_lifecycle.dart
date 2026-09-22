import 'package:flutter/widgets.dart';

import '../notifications/notification_delivery_mode.dart';

bool shouldPauseBackgroundSync(
  AppLifecycleState state,
  NotificationDeliveryMode mode, {
  required bool inCall,
}) =>
    state == AppLifecycleState.paused &&
    mode != NotificationDeliveryMode.backgroundService &&
    !inCall;

bool shouldResumeBackgroundSync(
  AppLifecycleState state,
  NotificationDeliveryMode mode,
) =>
    state == AppLifecycleState.resumed &&
    mode != NotificationDeliveryMode.backgroundService;
