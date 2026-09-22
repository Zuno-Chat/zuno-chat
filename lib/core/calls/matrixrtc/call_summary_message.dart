import 'package:matrix/matrix.dart';

import '../../format/human_units.dart';

const callSummaryMsgtype = 'im.zuno.call_summary';
const callInviteMsgtype = 'im.zuno.call_invite';
const callDeclineMsgtype = 'im.zuno.call_decline';

bool isCallSummaryMessage(String? msgtype) => msgtype == callSummaryMsgtype;

bool isCallInviteMessage(String? msgtype) => msgtype == callInviteMsgtype;

bool isCallDeclineMessage(String? msgtype) => msgtype == callDeclineMsgtype;

bool isCallSignalingMessage(String? msgtype) =>
    isCallInviteMessage(msgtype) || isCallDeclineMessage(msgtype);

enum CallSummaryStatus { missed, declined, ended }

class CallSummary {
  final String callId;
  final String kind;
  final CallSummaryStatus status;
  final int durationMs;

  const CallSummary({
    required this.callId,
    required this.kind,
    required this.status,
    required this.durationMs,
  });

  String get label => kind == 'video' ? 'Video call' : 'Voice call';

  String get displayBody => switch (status) {
    CallSummaryStatus.missed => 'Missed $label',
    CallSummaryStatus.declined => '$label declined',
    CallSummaryStatus.ended =>
      '$label · ${formatClock(Duration(milliseconds: durationMs))}',
  };

  Map<String, Object?> toMessageContent() => {
    'msgtype': callSummaryMsgtype,
    'body': displayBody,
    'call_id': callId,
    'kind': kind,
    'status': status.name,
    'duration_ms': durationMs,
  };

  static CallSummary? fromEvent(Event event) {
    if (!isCallSummaryMessage(event.messageType)) return null;
    final callId = event.content.tryGet<String>('call_id');
    final kind = event.content.tryGet<String>('kind');
    final statusName = event.content.tryGet<String>('status');
    if (callId == null || kind == null || statusName == null) return null;
    final status = CallSummaryStatus.values.asNameMap()[statusName];
    if (status == null) return null;
    return CallSummary(
      callId: callId,
      kind: kind,
      status: status,
      durationMs: event.content.tryGet<int>('duration_ms') ?? 0,
    );
  }
}

bool isMissedCallSummary(Event event) =>
    CallSummary.fromEvent(event)?.status == CallSummaryStatus.missed;
