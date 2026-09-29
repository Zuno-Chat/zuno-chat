import 'package:matrix/matrix.dart';

import '../calls/matrixrtc/call_unread_correction_provider.dart';
import 'optimistic_room_state.dart';
import 'room_access.dart';
import 'room_permission.dart';
import 'room_title.dart';

const communityPowerLevels = <String, Object?>{
  'events_default': 100,
  'state_default': 100,
  'invite': 0,
  'events': {EventTypes.SpaceChild: 50},
};

const _hierarchyPageSize = 50;

class RoomNotAddedToCommunity implements Exception {
  final String roomId;

  const RoomNotAddedToCommunity(this.roomId);

  @override
  String toString() => 'Room created, but not added to the community.';
}

bool isJoinedCommunity(Room room) =>
    room.isSpace && room.membership == Membership.join;

Set<String> communityChildIds(Room community) => {
  for (final child in community.spaceChildren) ?child.roomId,
};

bool _belongsInCommunity(Room room) =>
    room.membership == Membership.join && !room.isSpace && !room.isDirectChat;

int _newestFirst(Room a, Room b) =>
    b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);

List<Room> communityRooms(Room community, {Room? Function(String id)? lookup}) {
  final find = lookup ?? community.client.getRoomById;
  return [
    for (final id in communityChildIds(community))
      if (find(id) case final room? when _belongsInCommunity(room)) room,
  ]..sort(_newestFirst);
}

List<Room> communitiesOf(Room room) => [
  for (final candidate in room.client.rooms)
    if (isJoinedCommunity(candidate) &&
        communityChildIds(candidate).contains(room.id))
      candidate,
];

String? communityNameOf(Room room) {
  final communities = communitiesOf(room);
  return communities.isEmpty ? null : roomTitle(communities.first);
}

class HomeLayout {
  final List<Room> chatInvitations;
  final List<Room> chats;
  final List<Room> communityInvitations;
  final List<Room> communities;
  final Map<String, List<Room>> communityRooms;

  const HomeLayout({
    required this.chatInvitations,
    required this.chats,
    required this.communityInvitations,
    required this.communities,
    required this.communityRooms,
  });

  bool hasUnreadChats(Map<String, int> corrections) =>
      chatInvitations.isNotEmpty ||
      chats.any((room) => _hasUnread(room, corrections));

  bool hasUnreadCommunities(Map<String, int> corrections) =>
      communityInvitations.isNotEmpty ||
      communityRooms.values.any(
        (rooms) => rooms.any((room) => _hasUnread(room, corrections)),
      );
}

bool _hasUnread(Room room, Map<String, int> corrections) =>
    room.pushRuleState != PushRuleState.dontNotify &&
    displayedUnreadCount(corrections, room) > 0;

HomeLayout arrangeHome(
  List<Room> rooms, {
  Set<String> pendingJoins = const {},
}) {
  final chatInvitations = <Room>[];
  final communityInvitations = <Room>[];
  final communities = <Room>[];
  for (final room in rooms) {
    if (room.membership == Membership.invite) {
      if (pendingJoins.contains(room.id)) continue;
      (room.isSpace ? communityInvitations : chatInvitations).add(room);
    } else if (isJoinedCommunity(room)) {
      communities.add(room);
    }
  }

  final byId = {for (final room in rooms) room.id: room};
  final grouped = <String>{};
  final roomsByCommunity = <String, List<Room>>{};
  final activity = <String, DateTime>{};
  for (final community in communities) {
    final inside = communityRooms(community, lookup: (id) => byId[id]);
    roomsByCommunity[community.id] = inside;
    grouped.addAll(inside.map((room) => room.id));
    activity[community.id] = inside.isEmpty
        ? community.latestEventReceivedTime
        : inside.first.latestEventReceivedTime;
  }
  communities.sort((a, b) => activity[b.id]!.compareTo(activity[a.id]!));

  return HomeLayout(
    chatInvitations: chatInvitations,
    chats: [
      for (final room in rooms)
        if (room.membership == Membership.join &&
            !room.isSpace &&
            !grouped.contains(room.id))
          room,
    ],
    communityInvitations: communityInvitations,
    communities: communities,
    communityRooms: roomsByCommunity,
  );
}

List<Room> roomsLeavingWith(Room community) {
  final others = [
    for (final other in community.client.rooms)
      if (other.id != community.id && isJoinedCommunity(other))
        communityChildIds(other),
  ];
  return [
    for (final room in communityRooms(community))
      if (!others.any((ids) => ids.contains(room.id))) room,
  ];
}

Future<void> leaveCommunity(Room community) async {
  await Future.wait(roomsLeavingWith(community).map((room) => room.leave()));
  await community.leave();
}

Future<String> createCommunity(
  Client client, {
  required String name,
  required RoomAccess access,
}) async {
  final public = access == RoomAccess.public;
  final String id;
  try {
    id = await client.createRoom(
      name: name,
      creationContent: {'type': RoomCreationTypes.mSpace},
      preset: public
          ? CreateRoomPreset.publicChat
          : CreateRoomPreset.privateChat,
      visibility: public ? Visibility.public : null,
      powerLevelContentOverride: communityPowerLevels,
    );
  } on MatrixException catch (e) {
    if (isListingRefusal(e)) throw RoomListingRefused();
    rethrow;
  }
  await _awaitInSync(client, id);
  return id;
}

Future<String> createCommunityRoom(
  Room community, {
  required String name,
  RoomAccess access = RoomAccess.community,
}) async {
  final client = community.client;
  final via = [client.userID!.domain!];
  final roomId = await client.createGroupChat(
    groupName: name,
    enableEncryption: true,
    preset: CreateRoomPreset.privateChat,
    powerLevelContentOverride: defaultGroupPowerLevels(),
    waitForSync: false,
    initialState: [
      StateEvent(
        type: EventTypes.RoomJoinRules,
        content: switch (access) {
          RoomAccess.askToJoin => {'join_rule': JoinRules.knock.text},
          RoomAccess.private => {'join_rule': JoinRules.invite.text},
          RoomAccess.community || RoomAccess.public => {
            'join_rule': JoinRules.restricted.text,
            'allow': [
              {'type': 'm.room_membership', 'room_id': community.id},
            ],
          },
        },
      ),
      StateEvent(
        type: EventTypes.SpaceParent,
        stateKey: community.id,
        content: {'via': via, 'canonical': true},
      ),
    ],
  );
  try {
    await client.setRoomStateWithKey(
      community.id,
      EventTypes.SpaceChild,
      roomId,
      {'via': via},
    );
  } catch (_) {
    throw RoomNotAddedToCommunity(roomId);
  }
  applyOptimisticRoomState(community, EventTypes.SpaceChild, {
    'via': via,
  }, stateKey: roomId);
  await _awaitInSync(client, roomId);
  return roomId;
}

Future<void> _awaitInSync(Client client, String roomId) async {
  if (client.getRoomById(roomId) == null) {
    await client.waitForRoomInSync(roomId, join: true);
  }
}

Future<List<SpaceRoomsChunk$2>> joinableCommunityRooms(Room community) async {
  final client = community.client;
  final unjoined = communityChildIds(community)
      .where((id) => client.getRoomById(id)?.membership != Membership.join);
  if (unjoined.isEmpty) return const [];
  final response = await client.getSpaceHierarchy(
    community.id,
    maxDepth: 1,
    limit: _hierarchyPageSize,
  );
  return [
    for (final chunk in response.rooms)
      if (chunk.roomId != community.id &&
          chunk.roomType != RoomCreationTypes.mSpace &&
          client.getRoomById(chunk.roomId)?.membership != Membership.join)
        chunk,
  ];
}
