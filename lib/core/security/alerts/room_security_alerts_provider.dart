import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../matrix/room_changes.dart';
import '../security_providers.dart';
import 'security_alert.dart';
import 'security_alert_detection.dart';
import 'security_alerts_provider.dart';

const _membershipTypes = {EventTypes.RoomMember, EventTypes.RoomJoinRules};

final _roomMembershipProvider = StreamProvider.autoDispose.family<int, Room>((
  ref,
  room,
) async* {
  var revision = 0;
  yield revision;
  final changes = RoomChanges.where(
    room.client,
    states: (roomId, state) =>
        roomId == room.id && _membershipTypes.contains(state.type),
  );
  await for (final _ in changes.stream) {
    yield ++revision;
  }
});

final roomSecurityAlertsProvider = Provider.autoDispose
    .family<List<SecurityAlert>, Room>((ref, room) {
      ref.watch(_roomMembershipProvider(room));
      return roomSecurityAlerts(
        room,
        recorded: ref.watch(securityAlertsProvider),
        trustOf: (userId) => ref.watch(userTrustProvider(userId)),
      );
    });
