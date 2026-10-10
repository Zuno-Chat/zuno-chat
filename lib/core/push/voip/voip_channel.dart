import 'package:flutter/services.dart';

import '../../errors/caught_errors.dart';
import '../../platform/platform_capabilities.dart';
import '../keychain_unavailable.dart';

const voipChannel = MethodChannel('zuno/voip');

typedef VoipStatus = ({
  String? token,
  String environment,
  int kid,
  String key,
  bool callKit,
});

typedef VoipKey = ({int kid, String key});

typedef VoipDevExport = ({String token, int kid, String key});

enum VoipEvent { token, invalidated, keyMismatch }

class VoipChannel {
  const VoipChannel({PlatformCapabilities? capabilities})
    : _injectedCapabilities = capabilities;

  final PlatformCapabilities? _injectedCapabilities;

  bool get _enabled => (_injectedCapabilities ?? ambientCapabilities).voipRing;

  Future<VoipStatus?> status() async {
    final reply = await _invoke<Map<Object?, Object?>>('status');
    final kid = reply?['kid'];
    final key = reply?['key'];
    final environment = reply?['environment'];
    if (kid is! int || key is! String || environment is! String) return null;
    final token = reply?['token'];
    return (
      token: token is String && token.isNotEmpty ? token : null,
      environment: environment,
      kid: kid,
      key: key,
      callKit: reply?['callkit'] == true,
    );
  }

  Future<VoipKey?> rotateKey() async {
    final reply = await _invoke<Map<Object?, Object?>>('rotateKey');
    final kid = reply?['kid'];
    final key = reply?['key'];
    if (kid is! int || key is! String) return null;
    return (kid: kid, key: key);
  }

  Future<void> ackKey(int kid) => _invoke<void>('ackKey', {'kid': kid});

  Future<List<VoipEvent>> takeEvents() async {
    final reply = await _invoke<List<Object?>>('takeEvents');
    return [
      for (final event in reply ?? const <Object?>[])
        if (event is Map) ?VoipEvent.values.asNameMap()[event['type']],
    ];
  }

  Future<void> setSession({required bool signedIn}) =>
      _invoke<void>('setSession', {'signedIn': signedIn});

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
    if (!_enabled) return null;
    try {
      return await voipChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, s) {
      if (!isKeychainUnavailable(e)) reportCaught('voip $method', e.code, s);
      return null;
    }
  }
}
