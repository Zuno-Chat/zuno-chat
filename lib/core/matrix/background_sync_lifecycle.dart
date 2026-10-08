import 'package:flutter/widgets.dart';

import '../notifications/notification_delivery_mode.dart';

bool shouldPauseBackgroundSync(
  AppLifecycleState state,
  NotificationDeliveryMode mode, {
  required bool keepSyncAlive,
}) =>
    state == AppLifecycleState.paused &&
    mode != NotificationDeliveryMode.backgroundService &&
    !keepSyncAlive;

bool shouldResumeBackgroundSync(
  AppLifecycleState state,
  NotificationDeliveryMode mode,
) =>
    state == AppLifecycleState.resumed &&
    mode != NotificationDeliveryMode.backgroundService;

bool shouldLongPollInBackground(
  AppLifecycleState state,
  NotificationDeliveryMode mode, {
  required bool forCall,
  required bool forLiveShare,
}) =>
    state == AppLifecycleState.paused &&
    mode != NotificationDeliveryMode.backgroundService &&
    !forCall &&
    forLiveShare;
