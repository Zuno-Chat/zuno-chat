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

CallAudioRoute startingRoute(CallKind kind, Set<CallAudioRoute> headsets) =>
    _preferredHeadset(headsets) ??
    (kind == CallKind.video ? CallAudioRoute.speaker : CallAudioRoute.earpiece);

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
