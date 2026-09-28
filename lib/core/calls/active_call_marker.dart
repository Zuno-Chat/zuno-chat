import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

const _markerName = 'zuno/active_call';

void markCallActiveInProcess(bool active) {
  IsolateNameServer.removePortNameMapping(_markerName);
  if (!active) return;
  final marker = RawReceivePort()..close();
  IsolateNameServer.registerPortWithName(marker.sendPort, _markerName);
}

bool isCallActiveInProcess() =>
    IsolateNameServer.lookupPortByName(_markerName) != null;
