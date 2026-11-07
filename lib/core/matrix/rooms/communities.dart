import 'package:matrix/matrix.dart';

import '../../calls/matrixrtc/call_unread_correction_provider.dart';
import '../../errors/caught_errors.dart';
import 'optimistic_room_state.dart';
import 'permissions/room_permission.dart';
import 'room_access.dart';
import 'room_history.dart';
import 'room_mute.dart';

const communityPowerLevels = <String, Object?>{
  'events_default': 100,
  'state_default': 100,
  'invite': 0,
  'events': {EventTypes.SpaceChild: 50},
};

class RoomNotAddedToCommunity implements Exception {
  final String roomId;

  const RoomNotAddedToCommunity(this.roomId);

  @override
  String toString() => 'Room created, but not added to the community.';
}

bool isJoinedCommunity(Room room) =>
    room.isSpace && room.membership == Membership.join;

Set<String> communityChildIds(Room community) => {
  for (final MapEntry(key: id, value: link)
      in community.states[EventTypes.SpaceChild]?.entries ??
          const <MapEntry<String, StrippedStateEvent>>[])
    if (_hasVia(link)) id,
};

bool communityLists(Room community, String roomId) =>
    _hasVia(community.getState(EventTypes.SpaceChild, roomId));

bool _hasVia(StrippedStateEvent? link) =>
    link?.content.tryGetList<String>('via')?.isNotEmpty ?? false;

bool isJoinedGroupRoom(Room room) =>
    room.membership == Membership.join && !room.isSpace && !room.isDirectChat;

int newestActivityFirst(Room a, Room b) =>
    b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);

List<Room> communityRooms(Room community, {Iterable<Room>? among}) => [
  for (final room in among ?? community.client.rooms)
    if (communityLists(community, room.id) && isJoinedGroupRoom(room)) room,
]..sort(newestActivityFirst);

List<Room> communitiesOf(Room room) => [
  for (final candidate in room.client.rooms)
    if (isJoinedCommunity(candidate) && communityLists(candidate, room.id))
      candidate,
];

List<Room> mutualCommunitiesOf(Room room) {
  final named = {for (final parent in room.spaceParents) ?parent.roomId};
  return [
    for (final community in communitiesOf(room))
      if (named.contains(community.id)) community,
  ];
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
    !isRoomMuted(room) && displayedUnreadCount(corrections, room) > 0;

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

  final grouped = <String>{};
  final roomsByCommunity = <String, List<Room>>{};
  final activity = <String, DateTime>{};
  for (final community in communities) {
    final inside = communityRooms(community, among: rooms);
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

List<Room> roomsLeavingWith(Room community) => [
  for (final room in communityRooms(community))
    if (communitiesOf(room) case [final only] when only.id == community.id)
      room,
];

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
      newRoomHistoryState(),
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
  } catch (e, s) {
    reportCaught('add a room to its community', e, s);
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
