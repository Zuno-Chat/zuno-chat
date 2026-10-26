import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../errors/best_effort.dart';
import '../../matrix/room_roles.dart';
import '../module/calls_module.dart';
import 'call_member_state.dart';
import 'call_summary_message.dart';

const callMuteEventType = 'im.zuno.call.mute';
const callRemoveEventType = 'im.zuno.call.remove';

bool Function(String targetId) callModerationGate(
  Room room, {
  String? actorId,
}) => room.isDirectChat ? (_) => false : memberRemover(room, actorId: actorId);

sealed class CallModeration {
  const CallModeration({required this.callId, required this.userId});

  final String callId;
  final String userId;

  static CallModeration? fromEvent(Event event) {
    final callId = event.content.tryGet<String>('call_id');
    final userId = event.content.tryGet<String>('user_id');
    if (callId == null || userId == null) return null;
    return switch (event.type) {
      callMuteEventType => switch (event.content['membership_created_ts']) {
        final int joinedAt => CallMute(
          callId: callId,
          userId: userId,
          membershipCreatedTs: joinedAt,
        ),
        _ => null,
      },
      callRemoveEventType => CallRemoval(callId: callId, userId: userId),
      _ => null,
    };
  }
}

final class CallMute extends CallModeration {
  const CallMute({
    required super.callId,
    required super.userId,
    required this.membershipCreatedTs,
  });

  final int membershipCreatedTs;
}

final class CallRemoval extends CallModeration {
  const CallRemoval({required super.callId, required super.userId});
}

class CallModerationNotSent implements Exception {
  const CallModerationNotSent();

  @override
  String toString() => 'CallModerationNotSent';
}

Future<void> muteInCall(
  Room room, {
  required String callId,
  required String userId,
}) async {
  final join = _referencedJoin(room, callId, userId);
  if (join == null) return;
  await _tellCall(
    room,
    callMuteEventType,
    callId: callId,
    userId: userId,
    membershipEventId: join.eventId!,
    extra: {'membership_created_ts': join.membership.createdAtMs},
  );
}

Future<void> removeFromCall(
  Room room, {
  required String callId,
  required String userId,
  http.Client? httpClient,
}) async {
  await requestCallRemoval(
    room.client,
    roomId: room.id,
    callId: callId,
    userId: userId,
    httpClient: httpClient,
  );
  final join = _referencedJoin(room, callId, userId);
  if (join == null) return;
  await runBestEffort(
    () => _tellCall(
      room,
      callRemoveEventType,
      callId: callId,
      userId: userId,
      membershipEventId: join.eventId!,
      txid: 'zuno-remove-$callId-$userId',
    ),
    label: 'tell the call about a removal',
  );
}

CallJoin? _referencedJoin(Room room, String callId, String userId) => callJoins(
  room,
  callId,
).where((join) => join.userId == userId && join.eventId != null).firstOrNull;

Future<void> _tellCall(
  Room room,
  String type, {
  required String callId,
  required String userId,
  required String membershipEventId,
  Map<String, Object?> extra = const {},
  String? txid,
}) async {
  final sent = await room.sendEvent(
    {
      'call_id': callId,
      'user_id': userId,
      ...extra,
      'm.relates_to': callReference(membershipEventId),
    },
    type: type,
    txid: txid,
    displayPendingEvent: false,
  );
  if (sent == null) throw const CallModerationNotSent();
}
