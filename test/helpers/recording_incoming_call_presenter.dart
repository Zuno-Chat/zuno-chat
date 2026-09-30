import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';

typedef EndedRing = ({String? roomId, String? callId, RingEnd end});

class RecordingIncomingCallPresenter extends NoopIncomingCallPresenter {
  final ends = <EndedRing>[];

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {
    ends.add((roomId: roomId, callId: callId, end: end));
  }
}
