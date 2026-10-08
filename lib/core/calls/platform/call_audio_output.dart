import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../platform/platform_capabilities.dart';
import '../call_audio_route.dart';
import '../notifications/call_notification_service.dart';

const _callsChannel = MethodChannel('zuno/calls');

typedef CallAudioSnapshot = ({
  Set<CallAudioRoute> headsets,
  CallAudioRoute? route,
});

abstract interface class CallAudioOutput {
  Future<CallAudioSnapshot> read();

  Future<void> apply(CallAudioRoute route);

  void watch(void Function() onChanged);

  void unwatch();
}

CallAudioOutput callAudioOutputFor(PlatformCapabilities capabilities) =>
    capabilities.callKit ? CallKitCallAudioOutput() : WebRtcCallAudioOutput();

CallAudioSnapshot callAudioSnapshotFrom(Map<Object?, Object?>? state) {
  final byName = CallAudioRoute.values.asNameMap();
  final headsets = <CallAudioRoute>{};
  final names = state?['headsets'];
  if (names is List) {
    for (final name in names) {
      final headset = byName[name];
      if (headset != null) headsets.add(headset);
    }
  }
  return (headsets: headsets, route: byName[state?['route']]);
}

class WebRtcCallAudioOutput implements CallAudioOutput {
  void Function(dynamic)? _handler;

  @override
  Future<CallAudioSnapshot> read() async {
    try {
      final outputs = await Helper.audiooutputs;
      return (
        headsets: headsetsIn(
          outputs.map(
            (output) => (deviceId: output.deviceId, groupId: output.groupId),
          ),
        ),
        route: null,
      );
    } catch (_) {
      return (headsets: const <CallAudioRoute>{}, route: null);
    }
  }

  @override
  Future<void> apply(CallAudioRoute route) => switch (route) {
    CallAudioRoute.speaker => Helper.setSpeakerphoneOn(true),
    CallAudioRoute.earpiece => Helper.setSpeakerphoneOn(false),
    CallAudioRoute.wiredHeadset => Helper.selectAudioOutput('wired-headset'),
    CallAudioRoute.bluetooth => Helper.selectAudioOutput('bluetooth'),
  };

  @override
  void watch(void Function() onChanged) {
    void handler(dynamic _) => onChanged();
    _handler = handler;
    navigator.mediaDevices.ondevicechange = handler;
  }

  @override
  void unwatch() {
    final handler = _handler;
    _handler = null;
    if (handler != null && navigator.mediaDevices.ondevicechange == handler) {
      navigator.mediaDevices.ondevicechange = null;
    }
  }
}

class CallKitCallAudioOutput implements CallAudioOutput {
  StreamSubscription<Map<Object?, Object?>>? _changes;
  CallAudioSnapshot? _pushed;

  @override
  Future<CallAudioSnapshot> read() async {
    if (_pushed case final pushed?) {
      _pushed = null;
      return pushed;
    }
    try {
      return callAudioSnapshotFrom(
        await _callsChannel.invokeMapMethod<Object?, Object?>('audioRoute'),
      );
    } catch (_) {
      return (headsets: const <CallAudioRoute>{}, route: null);
    }
  }

  @override
  Future<void> apply(CallAudioRoute route) async {
    try {
      await _callsChannel.invokeMethod<void>('setAudioRoute', {
        'route': route.name,
      });
    } on MissingPluginException {
      return;
    }
  }

  @override
  void watch(void Function() onChanged) {
    unawaited(_changes?.cancel());
    _changes = CallNotificationService.instance.onAudioRouteChanged.listen((
      state,
    ) {
      _pushed = callAudioSnapshotFrom(state);
      onChanged();
    });
  }

  @override
  void unwatch() {
    unawaited(_changes?.cancel());
    _changes = null;
    _pushed = null;
  }
}
