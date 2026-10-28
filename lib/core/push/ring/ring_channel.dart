import 'package:flutter/services.dart';

import '../../errors/caught_errors.dart';
import '../../platform/platform_capabilities.dart';
import '../fcm/fcm_pusher.dart';
import '../keychain_unavailable.dart';

const ringChannel = MethodChannel('zuno/ring');

const voipProductionAppId = 'im.zuno.chat.ios.voip';
const voipDevelopmentAppId = 'im.zuno.chat.ios.dev.voip';

String voipAppIdFor(String environment) =>
    environment == 'development' ? voipDevelopmentAppId : voipProductionAppId;

typedef RingStatus = ({
  String? token,
  String environment,
  String appId,
  int kid,
  String key,
  bool canRing,
});

typedef VoipKey = ({int kid, String key});

typedef VoipDevExport = ({String token, int kid, String key});

enum RingRegistrationEvent { token, invalidated, keyMismatch }

class RingChannel {
  const RingChannel({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  Future<RingStatus?> status() async {
    final reply = await _invoke<Map<Object?, Object?>>('status');
    final kid = reply?['kid'];
    final key = reply?['key'];
    final environment = reply?['environment'];
    if (kid is! int || key is! String || environment is! String) return null;
    final token = reply?['token'];
    return (
      token: token is String && token.isNotEmpty ? token : null,
      environment: environment,
      appId: _capabilities.voipRing ? voipAppIdFor(environment) : fcmAppId,
      kid: kid,
      key: key,
      canRing: reply?['rings'] == true,
    );
  }

  Future<VoipKey?> rotateKey() async {
    final reply = await _invoke<Map<Object?, Object?>>('rotateKey');
    final kid = reply?['kid'];
    final key = reply?['key'];
    if (kid is! int || key is! String) return null;
    return (kid: kid, key: key);
  }

  Future<void> ackKey(int kid, {required int serverOffsetMs}) =>
      _invoke<void>('ackKey', {'kid': kid, 'serverOffsetMs': serverOffsetMs});

  Future<List<RingRegistrationEvent>> takeEvents() async {
    final reply = await _invoke<List<Object?>>('takeEvents');
    return [
      for (final event in reply ?? const <Object?>[])
        if (event is Map)
          ?RingRegistrationEvent.values.asNameMap()[event['type']],
    ];
  }

  Future<void> setSession({required bool signedIn, String? userId}) =>
      _invoke<void>('setSession', {'signedIn': signedIn, 'userId': ?userId});

  Future<VoipDevExport?> devExport() async {
    final reply = await _invoke<Map<Object?, Object?>>('devExport');
    final token = reply?['token'];
    final kid = reply?['kid'];
    final key = reply?['key'];
    if (reply?['environment'] != 'development' ||
        token is! String ||
        kid is! int ||
        key is! String) {
      return null;
    }
    return (token: token, kid: kid, key: key);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await ringChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, s) {
      if (!isKeychainUnavailable(e)) reportCaught('ring $method', e.code, s);
      return null;
    }
  }
}
