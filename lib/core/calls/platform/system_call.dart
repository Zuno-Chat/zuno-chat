import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

enum SystemCallEnd { remoteEnded, unanswered, failed }

typedef SystemCallStart = ({bool muted});

const _unmuted = (muted: false);

abstract interface class SystemCall {
  Future<SystemCallStart> begin({
    required String roomId,
    required String callId,
    required String title,
    required bool isVideo,
  });

  Future<void> connected({required String roomId, required String callId});

  Future<void> setMuted({
    required String roomId,
    required String callId,
    required bool muted,
  });

  Future<void> upgradeToVideo({required String roomId, required String callId});

  Future<void> end({
    required String roomId,
    required String callId,
    required SystemCallEnd end,
    required bool byUser,
  });
}

SystemCall systemCallFor(PlatformCapabilities capabilities) =>
    capabilities.callKit ? const CallKitSystemCall() : const NoopSystemCall();

final systemCallProvider = Provider<SystemCall>(
  (ref) => systemCallFor(ref.watch(platformCapabilitiesProvider)),
);

class CallKitSystemCall implements SystemCall {
  const CallKitSystemCall();

  @override
  Future<SystemCallStart> begin({
    required String roomId,
    required String callId,
    required String title,
    required bool isVideo,
  }) async {
    try {
      final state = await _callsChannel.invokeMapMethod<String, Object?>(
        'startSystemCall',
        {
          'roomId': roomId,
          'callId': callId,
          'title': title,
          'isVideo': isVideo,
        },
      );
      return (muted: state?['muted'] == true);
    } on MissingPluginException {
      return _unmuted;
    }
  }

  @override
  Future<void> connected({required String roomId, required String callId}) =>
      _invoke('reportCallConnected', {'roomId': roomId, 'callId': callId});

  @override
  Future<void> setMuted({
    required String roomId,
    required String callId,
    required bool muted,
  }) => _invoke('setCallMuted', {
    'roomId': roomId,
    'callId': callId,
    'muted': muted,
  });

  @override
  Future<void> upgradeToVideo({
    required String roomId,
    required String callId,
  }) => _invoke('upgradeCallToVideo', {'roomId': roomId, 'callId': callId});

  @override
  Future<void> end({
    required String roomId,
    required String callId,
    required SystemCallEnd end,
    required bool byUser,
  }) => _invoke('endSystemCall', {
    'roomId': roomId,
    'callId': callId,
    'reason': end.name,
    'byUser': byUser,
  });

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      await _callsChannel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    }
  }
}

class NoopSystemCall implements SystemCall {
  const NoopSystemCall();

  @override
  Future<SystemCallStart> begin({
    required String roomId,
    required String callId,
    required String title,
    required bool isVideo,
  }) async => _unmuted;

  @override
  Future<void> connected({
    required String roomId,
    required String callId,
  }) async {}

  @override
  Future<void> setMuted({
    required String roomId,
    required String callId,
    required bool muted,
  }) async {}

  @override
  Future<void> upgradeToVideo({
    required String roomId,
    required String callId,
  }) async {}

  @override
  Future<void> end({
    required String roomId,
    required String callId,
    required SystemCallEnd end,
    required bool byUser,
  }) async {}
}
