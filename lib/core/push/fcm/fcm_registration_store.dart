import 'package:shared_preferences/shared_preferences.dart';

const _tokenKey = 'push.fcm.token';

Future<void> saveFcmRegistration(
  SharedPreferences prefs, {
  required String token,
}) async {
  await prefs.setString(_tokenKey, token);
}

String? readFcmRegistration(SharedPreferences prefs) {
  final token = prefs.getString(_tokenKey);
  if (token == null || token.isEmpty) return null;
  return token;
}

Future<void> clearFcmRegistration(SharedPreferences prefs) async {
  await prefs.remove(_tokenKey);
}
