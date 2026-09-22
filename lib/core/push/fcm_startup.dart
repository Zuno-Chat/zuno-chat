import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'fcm_background_handler.dart';

bool isDuplicateFirebaseAppError(Object error) =>
    error is FirebaseException && error.code == 'duplicate-app';

Future<void> initializeFcmDelivery() async {
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
