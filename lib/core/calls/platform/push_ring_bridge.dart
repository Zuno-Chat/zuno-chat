import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/caught_errors.dart';
import '../../platform/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

abstract interface class PushRingBridge {
  Future<void> updateIncoming({
    required String roomId,
    required String callId,
    required String name,
    required bool video,
  });

  Future<bool> bindIncoming({
    required String uuid,
    required String roomId,
    required String callId,
    required String callerId,
    required String name,
    required bool video,
  });

  Future<void> endUnbound(String uuid);

  Future<void> declineSent({required String roomId, required String callId});
}

PushRingBridge pushRingBridgeFor(PlatformCapabilities capabilities) =>
    capabilities.voipRing
    ? const CallKitPushRingBridge()
    : const NoopPushRingBridge();

final pushRingBridgeProvider = Provider<PushRingBridge>(
  (ref) => pushRingBridgeFor(ref.watch(platformCapabilitiesProvider)),
);

class CallKitPushRingBridge implements PushRingBridge {
  const CallKitPushRingBridge();

  @override
  Future<void> updateIncoming({
    required String roomId,
    required String callId,
    required String name,
    required bool video,
  }) => _invoke<void>('updateIncoming', {
    'roomId': roomId,
    'callId': callId,
    'name': name,
    'video': video,
  });

  @override
  Future<bool> bindIncoming({
    required String uuid,
    required String roomId,
    required String callId,
    required String callerId,
    required String name,
    required bool video,
  }) async =>
      await _invoke<bool>('bindIncoming', {
        'uuid': uuid,
        'roomId': roomId,
        'callId': callId,
        'callerId': callerId,
        'name': name,
        'video': video,
      }) ??
      false;

  @override
  Future<void> endUnbound(String uuid) =>
      _invoke<void>('endUnbound', {'uuid': uuid});

  @override
  Future<void> declineSent({required String roomId, required String callId}) =>
      _invoke<void>('declineSent', {'roomId': roomId, 'callId': callId});

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await _callsChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e, s) {
      reportCaught('callkit $method', e, s);
      return null;
    }
  }
}

class NoopPushRingBridge implements PushRingBridge {
  const NoopPushRingBridge();

  @override
  Future<void> updateIncoming({
    required String roomId,
    required String callId,
    required String name,
    required bool video,
  }) async {}

  @override
  Future<bool> bindIncoming({
    required String uuid,
    required String roomId,
    required String callId,
    required String callerId,
    required String name,
    required bool video,
  }) async => false;

  @override
  Future<void> endUnbound(String uuid) async {}

  @override
  Future<void> declineSent({
    required String roomId,
    required String callId,
  }) async {}
}
