import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/optimistic_room_state.dart';
import '../matrixrtc/call_member_state.dart';
import '../matrixrtc/incoming_call.dart';
import '../models/call_kind.dart';

final serverRingsProvider = Provider<StreamController<ServerRing>>((ref) {
  final rings = StreamController<ServerRing>.broadcast(sync: true);
  ref.onDispose(rings.close);
  return rings;
});

class ServerRing {
  const ServerRing({
    required this.roomId,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.roomName,
    required this.kind,
    required this.appInFront,
    this.ringFor,
  });

  final String roomId;
  final String callId;
  final String callerId;
  final String callerName;
  final String roomName;
  final CallKind kind;
  final bool appInFront;
  final Duration? ringFor;

  static ServerRing? from(Object? arguments) {
    if (arguments is! Map) return null;
    final roomId = arguments['room'];
    final callId = arguments['call'];
    final callerId = arguments['caller'];
    if (roomId is! String || roomId.isEmpty) return null;
    if (callId is! String || callId.isEmpty) return null;
    if (callerId is! String || callerId.isEmpty) return null;
    final callerName = arguments['cname'];
    final roomName = arguments['rname'];
    return ServerRing(
      roomId: roomId,
      callId: callId,
      callerId: callerId,
      callerName: callerName is String ? callerName : '',
      roomName: roomName is String ? roomName : '',
      kind: arguments['kind'] == 'video' ? CallKind.video : CallKind.voice,
      appInFront: arguments['appInFront'] == true,
      ringFor: switch (arguments['ringMs']) {
        final int ms => Duration(milliseconds: ms),
        _ => null,
      },
    );
  }
}

IncomingCall? incomingCallFromServerRing(Client client, ServerRing ring) {
  if (ring.callerId == client.userID) return null;
  final known = client.getRoomById(ring.roomId);
  if (known != null && !canPublishCallMemberState(known)) return null;
  return IncomingCall(
    room: known ?? _roomNamedBy(client, ring),
    callId: ring.callId,
    callerId: ring.callerId,
    kind: ring.kind,
    ringFor: ring.ringFor,
  );
}

Room _roomNamedBy(Client client, ServerRing ring) {
  final room = Room(id: ring.roomId, client: client);
  final name = ring.roomName.isNotEmpty ? ring.roomName : ring.callerName;
  if (name.isNotEmpty) {
    applyOptimisticRoomState(room, EventTypes.RoomName, {'name': name});
  }
  if (ring.callerName.isNotEmpty) {
    room.setState(
      User(ring.callerId, displayName: ring.callerName, room: room),
    );
  }
  return room;
}
