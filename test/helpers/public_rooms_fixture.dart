import 'dart:convert';

import 'package:matrix/matrix.dart';

final publicRoomsFixture = <PublishedRoomsChunk>[
  PublishedRoomsChunk(
    roomId: '!chess:example.org',
    name: 'Chess club',
    canonicalAlias: '#chess:example.org',
    topic: 'Openings and endgames',
    numJoinedMembers: 12,
    joinRule: 'public',
    guestCanJoin: false,
    worldReadable: true,
  ),
  PublishedRoomsChunk(
    roomId: '!garden:example.org',
    name: 'Gardening',
    topic: 'Seeds, soil and seasons',
    numJoinedMembers: 4,
    joinRule: 'public',
    guestCanJoin: false,
    worldReadable: false,
  ),
  PublishedRoomsChunk(
    roomId: '!knit:example.org',
    name: 'Knitting circle',
    numJoinedMembers: 1,
    joinRule: 'public',
    guestCanJoin: false,
    worldReadable: false,
  ),
  PublishedRoomsChunk(
    roomId: '!hobbies:example.org',
    name: 'Hobbies',
    roomType: 'm.space',
    numJoinedMembers: 30,
    joinRule: 'public',
    guestCanJoin: false,
    worldReadable: false,
  ),
];

List<PublishedRoomsChunk> publicRoomsMatching(
  String? term, {
  List<Object?>? roomTypes,
}) {
  final needle = term?.toLowerCase() ?? '';
  return publicRoomsFixture
      .where(
        (r) =>
            (roomTypes == null || roomTypes.contains(r.roomType)) &&
            ((r.name ?? '').toLowerCase().contains(needle) ||
                (r.topic ?? '').toLowerCase().contains(needle)),
      )
      .toList();
}

String publicRoomsFixtureJson({String? term, List<Object?>? roomTypes}) =>
    jsonEncode(
      QueryPublicRoomsResponse(
        chunk: publicRoomsMatching(term, roomTypes: roomTypes),
      ).toJson(),
    );
