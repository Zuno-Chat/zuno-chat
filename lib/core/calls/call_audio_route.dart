import 'models/call_kind.dart';

enum CallAudioRoute { earpiece, speaker, wiredHeadset, bluetooth }

CallAudioRoute? _preferredHeadset(Set<CallAudioRoute> headsets) {
  if (headsets.contains(CallAudioRoute.bluetooth)) {
    return CallAudioRoute.bluetooth;
  }
  if (headsets.contains(CallAudioRoute.wiredHeadset)) {
    return CallAudioRoute.wiredHeadset;
  }
  return null;
}

CallAudioRoute startingRoute(
  CallKind kind,
  Set<CallAudioRoute> headsets, {
  CallAudioRoute? continuing,
}) {
  if (continuing != null && _keeps(continuing, kind, headsets)) {
    return continuing;
  }
  return _preferredHeadset(headsets) ??
      (kind == CallKind.video
          ? CallAudioRoute.speaker
          : CallAudioRoute.earpiece);
}

bool _keeps(
  CallAudioRoute route,
  CallKind kind,
  Set<CallAudioRoute> headsets,
) => switch (route) {
  CallAudioRoute.speaker => true,
  CallAudioRoute.earpiece => kind == CallKind.voice,
  CallAudioRoute.wiredHeadset ||
  CallAudioRoute.bluetooth => headsets.contains(route),
};

CallAudioRoute toggledRoute(
  CallAudioRoute route,
  Set<CallAudioRoute> headsets,
) => route == CallAudioRoute.speaker
    ? _preferredHeadset(headsets) ?? CallAudioRoute.earpiece
    : CallAudioRoute.speaker;

CallAudioRoute? routeAfterHeadsetChange({
  required CallAudioRoute route,
  required Set<CallAudioRoute> before,
  required Set<CallAudioRoute> after,
  required CallKind kind,
}) {
  final connected = _preferredHeadset(after.difference(before));
  if (connected != null) return connected;
  final lostRoute = before.contains(route) && !after.contains(route);
  return lostRoute ? startingRoute(kind, after) : null;
}
