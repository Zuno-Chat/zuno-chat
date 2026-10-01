import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../notifications/notification_delivery_mode.dart';
import '../platform/platform_capabilities.dart';

enum FcmAvailability {
  available,
  updateRequired,
  disabled,
  unavailable,
  notConfigured,
  unknown,
}

enum FcmTokenFailure { noPlayServices, notConfigured, unavailable, failed }

class FcmTokenException implements Exception {
  const FcmTokenException(this.failure, [this.message]);

  final FcmTokenFailure failure;
  final String? message;

  @override
  String toString() => message == null
      ? 'FcmTokenException(${failure.name})'
      : 'FcmTokenException(${failure.name}: $message)';
}

class FcmPush {
  const FcmPush({
    required this.id,
    required this.data,
    required this.appInFront,
  });

  final String id;
  final Map<String, dynamic> data;
  final bool appInFront;
}

typedef FcmPushHandler = Future<void> Function(FcmPush push);

typedef FcmTokenHandler = Future<void> Function(String token);

class FcmBridge {
  FcmBridge({
    PlatformCapabilities? capabilities,
    this.channel = const MethodChannel('zuno/fcm'),
  }) : _injectedCapabilities = capabilities;

  static final FcmBridge instance = FcmBridge();

  final PlatformCapabilities? _injectedCapabilities;
  final MethodChannel channel;
  final _tokenRefreshes = StreamController<String>.broadcast();

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  bool get offered =>
      _capabilities.deliveryModes.contains(NotificationDeliveryMode.fcm);

  Stream<String> get tokenRefreshes => _tokenRefreshes.stream;

  Future<FcmAvailability> availability() async {
    if (!offered) return FcmAvailability.unavailable;
    try {
      return _availabilityFrom(
        await channel.invokeMethod<String>('availability'),
      );
    } catch (e) {
      debugPrint('zuno/push: FCM availability check failed ($e)');
      return FcmAvailability.unknown;
    }
  }

  Future<FcmAvailability> fixPlayServices() async {
    if (!offered) return FcmAvailability.unavailable;
    try {
      return _availabilityFrom(
        await channel.invokeMethod<String>('fixPlayServices'),
      );
    } catch (e) {
      debugPrint('zuno/push: Google Play services fix refused ($e)');
      return availability();
    }
  }

  Future<String?> getToken() async {
    if (!offered) return null;
    final String? token;
    try {
      token = await channel.invokeMethod<String>('getToken');
    } on PlatformException catch (e) {
      throw FcmTokenException(_failureFrom(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw FcmTokenException(FcmTokenFailure.failed, e.message);
    }
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> deleteToken() async {
    if (!offered) return;
    await channel.invokeMethod<void>('deleteToken');
  }

  void serve({
    required FcmPushHandler onPush,
    FcmTokenHandler? onToken,
    Future<bool> Function()? isQuiescent,
  }) {
    if (!offered) return;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'push':
          final push = _pushFrom(call.arguments);
          if (push == null) {
            debugPrint('zuno/push: FCM push without an id, ignored');
            return null;
          }
          await onPush(push);
          return null;
        case 'token':
          final token = _tokenFrom(call.arguments);
          if (token == null) return null;
          if (onToken != null) {
            await onToken(token);
          } else {
            _tokenRefreshes.add(token);
          }
          return null;
        case 'quiescent':
          return _quiet(isQuiescent);
      }
      throw MissingPluginException('zuno/fcm has no ${call.method}');
    });
  }

  Future<bool> ready() async {
    if (!offered) return false;
    try {
      return await channel.invokeMethod<bool>('ready') ?? false;
    } catch (e) {
      debugPrint(
        'zuno/push: could not tell the FCM router this engine is '
        'ready ($e)',
      );
      return false;
    }
  }
}

Future<bool> _quiet(Future<bool> Function()? isQuiescent) async {
  if (isQuiescent == null) return false;
  try {
    return await isQuiescent();
  } catch (e) {
    debugPrint('zuno/push: could not settle this push engine ($e)');
    return false;
  }
}

FcmAvailability _availabilityFrom(String? name) => switch (name) {
  'available' => FcmAvailability.available,
  'updateRequired' => FcmAvailability.updateRequired,
  'disabled' => FcmAvailability.disabled,
  'unavailable' => FcmAvailability.unavailable,
  'notConfigured' => FcmAvailability.notConfigured,
  _ => FcmAvailability.unknown,
};

FcmTokenFailure _failureFrom(String code) => switch (code) {
  'noPlayServices' => FcmTokenFailure.noPlayServices,
  'notConfigured' => FcmTokenFailure.notConfigured,
  'unavailable' => FcmTokenFailure.unavailable,
  _ => FcmTokenFailure.failed,
};

FcmPush? _pushFrom(Object? arguments) {
  if (arguments is! Map) return null;
  final id = arguments['id'];
  final data = arguments['data'];
  if (id is! String || id.isEmpty || data is! Map) return null;
  return FcmPush(
    id: id,
    data: {
      for (final MapEntry(:key, :value) in data.entries)
        if (key is String) key: value,
    },
    appInFront: arguments['appInFront'] == true,
  );
}

String? _tokenFrom(Object? arguments) {
  if (arguments is! Map) return null;
  final token = arguments['token'];
  if (token is! String || token.isEmpty) return null;
  return token;
}
