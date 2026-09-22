import 'package:shared_preferences/shared_preferences.dart';

const _endpointKey = 'push.unified_push.endpoint';
const _gatewayKey = 'push.unified_push.gateway';
const _pushkeyKey = 'push.unified_push.pushkey';
const _authKey = 'push.unified_push.auth';

class UnifiedPushRegistration {
  final Uri endpointUrl;
  final Uri? gatewayUrl;
  final String pushkey;
  final String? auth;

  const UnifiedPushRegistration({
    required this.endpointUrl,
    this.gatewayUrl,
    String? pushkey,
    this.auth,
  }) : pushkey = pushkey ?? '';

  String get effectivePushkey =>
      pushkey.isEmpty ? endpointUrl.toString() : pushkey;
}

Future<void> saveUnifiedPushRegistration(
  SharedPreferences prefs, {
  required Uri endpointUrl,
  Uri? gatewayUrl,
  String? pushkey,
  String? auth,
}) async {
  await prefs.setString(_endpointKey, endpointUrl.toString());
  if (gatewayUrl == null) {
    await prefs.remove(_gatewayKey);
  } else {
    await prefs.setString(_gatewayKey, gatewayUrl.toString());
  }
  if (pushkey == null || pushkey == endpointUrl.toString()) {
    await prefs.remove(_pushkeyKey);
  } else {
    await prefs.setString(_pushkeyKey, pushkey);
  }
  if (auth == null) {
    await prefs.remove(_authKey);
  } else {
    await prefs.setString(_authKey, auth);
  }
}

UnifiedPushRegistration? readUnifiedPushRegistration(SharedPreferences prefs) {
  final endpoint = Uri.tryParse(prefs.getString(_endpointKey) ?? '');
  if (endpoint == null || !endpoint.hasScheme) return null;
  final storedGateway = prefs.getString(_gatewayKey);
  final gateway = storedGateway == null ? null : Uri.tryParse(storedGateway);
  return UnifiedPushRegistration(
    endpointUrl: endpoint,
    gatewayUrl: gateway?.hasScheme == true ? gateway : null,
    pushkey: prefs.getString(_pushkeyKey) ?? endpoint.toString(),
    auth: prefs.getString(_authKey),
  );
}

Future<void> clearUnifiedPushRegistration(SharedPreferences prefs) async {
  await prefs.remove(_endpointKey);
  await prefs.remove(_gatewayKey);
  await prefs.remove(_pushkeyKey);
  await prefs.remove(_authKey);
}
