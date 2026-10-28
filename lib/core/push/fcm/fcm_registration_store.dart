import 'package:shared_preferences/shared_preferences.dart';

const fcmTokenKey = 'push.fcm.token';
const fcmPendingTokenKey = 'push.fcm.pendingToken';

Future<void> saveFcmRegistration(
  SharedPreferences prefs, {
  required String token,
}) async {
  await prefs.setString(fcmTokenKey, token);
}

String? readFcmRegistration(SharedPreferences prefs) {
  final token = prefs.getString(fcmTokenKey);
  if (token == null || token.isEmpty) return null;
  return token;
}

Future<void> clearFcmRegistration(SharedPreferences prefs) async {
  await prefs.remove(fcmTokenKey);
}
