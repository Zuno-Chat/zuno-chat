import 'dart:async';

import 'package:flutter/services.dart';

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

  Future<CallAudioSnapshot?> begin(CallAudioRoute route);

  Future<void> apply(CallAudioRoute route);

  void watch(void Function() onChanged);

  void unwatch();

  Future<void> end();
}

CallAudioOutput callAudioOutputFor(PlatformCapabilities capabilities) {
  if (capabilities.callKit) return NativeCallAudioOutput(startsSession: false);
  if (capabilities.nativeCallAudio) {
    return NativeCallAudioOutput(startsSession: true);
  }
  return const NoCallAudioOutput();
}

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

class NativeCallAudioOutput implements CallAudioOutput {
  NativeCallAudioOutput({required this.startsSession});

  final bool startsSession;
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
  Future<CallAudioSnapshot?> begin(CallAudioRoute route) async {
    if (!startsSession) return null;
    try {
      return callAudioSnapshotFrom(
        await _callsChannel.invokeMapMethod<Object?, Object?>(
          'startCallAudio',
          {'route': route.name},
        ),
      );
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> apply(CallAudioRoute route) =>
      _invoke('setAudioRoute', {'route': route.name});

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

  @override
  Future<void> end() async {
    if (!startsSession) return;
    await _invoke('stopCallAudio');
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _callsChannel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    }
  }
}

class NoCallAudioOutput implements CallAudioOutput {
  const NoCallAudioOutput();

  @override
  Future<CallAudioSnapshot> read() async =>
      (headsets: const <CallAudioRoute>{}, route: null);

  @override
  Future<CallAudioSnapshot?> begin(CallAudioRoute route) async => null;

  @override
  Future<void> apply(CallAudioRoute route) async {}

  @override
  void watch(void Function() onChanged) {}

  @override
  void unwatch() {}

  @override
  Future<void> end() async {}
}
