import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../notifications/notification_delivery_mode.dart';
import '../platform/platform_capabilities.dart';
import 'fcm_background_handler.dart';

bool isDuplicateFirebaseAppError(Object error) =>
    error is FirebaseException && error.code == 'duplicate-app';

Future<void> initializeFcmDelivery({PlatformCapabilities? capabilities}) async {
  final modes = (capabilities ?? ambientCapabilities).deliveryModes;
  if (!modes.contains(NotificationDeliveryMode.fcm)) return;
  try {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      if (!isDuplicateFirebaseAppError(error)) rethrow;
      debugPrint(
        'zuno/push: Firebase app already initialized (hot restart), '
        'continuing',
      );
    }
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    listenForForegroundFcmMessages();
  } catch (error, stack) {
    debugPrint(
      'zuno/push: FCM setup failed, continuing without it: $error\n$stack',
    );
  }
}
