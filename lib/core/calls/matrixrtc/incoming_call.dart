import 'package:matrix/matrix.dart';

import '../models/call_kind.dart';

class IncomingCall {
  final Room room;
  final String callId;
  final String callerId;
  final CallKind kind;

  const IncomingCall({
    required this.room,
    required this.callId,
    required this.callerId,
    required this.kind,
  });
}
