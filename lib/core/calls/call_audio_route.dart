import 'models/call_kind.dart';

enum CallAudioRoute { earpiece, speaker, wiredHeadset, bluetooth }

const _bluetoothPortTypes = {
  'BluetoothHFP',
  'BluetoothA2DPOutput',
  'BluetoothLE',
};

const _wiredPortTypes = {'Headphones', 'USBAudio'};

Set<CallAudioRoute> headsetsIn(
  Iterable<({String deviceId, String? groupId})> outputs,
) => {
  for (final output in outputs)
    if (output.deviceId == 'bluetooth' ||
        _bluetoothPortTypes.contains(output.groupId))
      CallAudioRoute.bluetooth
    else if (output.deviceId == 'wired-headset' ||
        _wiredPortTypes.contains(output.groupId))
      CallAudioRoute.wiredHeadset,
};

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
