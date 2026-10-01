import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart' show Client;

import '../notifications/fcm_delivery_provider.dart';
import 'fcm_bridge.dart';
import 'fcm_headless_entry.dart';

Future<void> initializeFcmDelivery({FcmBridge? bridge}) async {
  final fcm = bridge ?? FcmBridge.instance;
  if (!fcm.offered) return;
  fcm.serve(onPush: (push) => handleFcmPush(fcmDeliveryProvider.runner, push));
}

void attachFcmAppClient(Client client, {FcmBridge? bridge}) {
  final fcm = bridge ?? FcmBridge.instance;
  if (!fcm.offered) return;
  fcmDeliveryProvider.runner.liveClient = client;
}

Future<bool> markFcmAppReady({FcmBridge? bridge}) async {
  final fcm = bridge ?? FcmBridge.instance;
  if (!fcm.offered || fcmDeliveryProvider.runner.liveClient == null) {
    return false;
  }
  final taken = await fcm.ready();
  if (!taken) debugPrint('zuno/push: the FCM router did not take the app');
  return taken;
}
