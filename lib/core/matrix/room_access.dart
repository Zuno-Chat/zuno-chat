import 'package:matrix/matrix.dart';

import 'communities.dart';
import 'optimistic_room_state.dart';
import 'room_permission.dart';
import 'room_roles.dart';

enum RoomAccess { public, community, askToJoin, private }

extension RoomAccessX on RoomAccess {
  String get label => switch (this) {
    RoomAccess.public => 'Public',
    RoomAccess.community => 'Community',
    RoomAccess.askToJoin => 'Ask to join',
    RoomAccess.private => 'Private',
  };

  String get description => switch (this) {
    RoomAccess.public => 'Anyone can find and join',
    RoomAccess.community => 'Members of the community can join',
    RoomAccess.askToJoin => 'Members can ask; a moderator lets them in',
    RoomAccess.private => 'Invite only',
  };
}

class RoomListingRefused implements Exception {
  @override
  String toString() => 'Public rooms cannot be listed here';
}

RoomAccess roomAccessOf(Room room) => switch (room.joinRules) {
  JoinRules.public => RoomAccess.public,
  JoinRules.restricted || JoinRules.knockRestricted => RoomAccess.community,
  JoinRules.knock => RoomAccess.askToJoin,
  _ => RoomAccess.private,
};

bool canChangeRoomAccess(Room room) =>
    !room.isDirectChat && ownRoomRole(room) == RoomRole.admin;

Future<String> createGroupRoom(
  Client client, {
  required String name,
  required RoomAccess access,
}) async {
  final public = access == RoomAccess.public;
  try {
    return await client.createGroupChat(
      groupName: name,
      enableEncryption: true,
      preset: public
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      visibility: public ? Visibility.public : null,
      powerLevelContentOverride: defaultGroupPowerLevels(public: public),
    );
  } on MatrixException catch (e) {
    if (isListingRefusal(e)) throw RoomListingRefused();
    rethrow;
  }
}

Future<void> setRoomAccess(Room room, RoomAccess access) async {
  switch (access) {
    case RoomAccess.public:
      await _setListed(room, Visibility.public);
      await _setJoinRule(room, JoinRules.public);
    case RoomAccess.community:
      final communities = communitiesOf(room).map((c) => c.id).toList();
      if (communities.isEmpty) throw StateError('No community holds this room');
      await _setJoinRule(room, JoinRules.restricted, allow: communities);
      await _setListed(room, Visibility.private);
    case RoomAccess.askToJoin:
      await _setJoinRule(room, JoinRules.knock);
      await _setListed(room, Visibility.private);
    case RoomAccess.private:
      await _setJoinRule(room, JoinRules.invite);
      await _setListed(room, Visibility.private);
  }
}

Future<void> _setJoinRule(
  Room room,
  JoinRules joinRule, {
  List<String>? allow,
}) async {
  await room.setJoinRules(joinRule, allowConditionRoomIds: allow);
  applyOptimisticRoomState(room, EventTypes.RoomJoinRules, {
    'join_rule': joinRule.text,
    if (allow != null)
      'allow': [
        for (final id in allow) {'type': 'm.room_membership', 'room_id': id},
      ],
  });
}

Future<void> _setListed(Room room, Visibility visibility) async {
  try {
    await room.client.setRoomVisibilityOnDirectory(
      room.id,
      visibility: visibility,
    );
  } on MatrixException catch (e) {
    if (isListingRefusal(e)) throw RoomListingRefused();
    rethrow;
  }
}

bool isListingRefusal(MatrixException e) =>
    e.errorMessage.toLowerCase().contains('not allowed to publish');
