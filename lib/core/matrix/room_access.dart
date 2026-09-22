import 'package:matrix/matrix.dart';

import 'optimistic_room_state.dart';
import 'room_permission.dart';
import 'room_roles.dart';

enum RoomAccess { public, private }

extension RoomAccessX on RoomAccess {
  String get label => switch (this) {
    RoomAccess.public => 'Public',
    RoomAccess.private => 'Private',
  };

  String get description => switch (this) {
    RoomAccess.public => 'Anyone can find and join',
    RoomAccess.private => 'Invite only',
  };
}

class RoomListingRefused implements Exception {
  @override
  String toString() => 'Public rooms cannot be listed here';
}

RoomAccess roomAccessOf(Room room) =>
    room.joinRules == JoinRules.public ? RoomAccess.public : RoomAccess.private;

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
    if (_isListingRefusal(e)) throw RoomListingRefused();
    rethrow;
  }
}

Future<void> setRoomAccess(Room room, RoomAccess access) async {
  switch (access) {
    case RoomAccess.public:
      await _setListed(room, Visibility.public);
      await _setJoinRule(room, JoinRules.public);
    case RoomAccess.private:
      await _setJoinRule(room, JoinRules.invite);
      await _setListed(room, Visibility.private);
  }
}

Future<void> _setJoinRule(Room room, JoinRules joinRule) async {
  await room.setJoinRules(joinRule);
  applyOptimisticRoomState(room, EventTypes.RoomJoinRules, {
    'join_rule': joinRule.text,
  });
}

Future<void> _setListed(Room room, Visibility visibility) async {
  try {
    await room.client.setRoomVisibilityOnDirectory(
      room.id,
      visibility: visibility,
    );
  } on MatrixException catch (e) {
    if (_isListingRefusal(e)) throw RoomListingRefused();
    rethrow;
  }
}

bool _isListingRefusal(MatrixException e) =>
    e.errorMessage.toLowerCase().contains('not allowed to publish');
