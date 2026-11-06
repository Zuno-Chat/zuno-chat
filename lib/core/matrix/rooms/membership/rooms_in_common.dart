import 'package:matrix/matrix.dart';

import '../communities.dart';

const _stableFlag = 'uk.half-shot.msc2666.query_mutual_rooms.stable';
const _specVersion = (major: 1, minor: 19);
final _versionPattern = RegExp(r'^v(\d+)\.(\d+)$');

Future<List<Room>> roomsInCommon(Room here, String userId) async {
  final client = here.client;
  if (!await _serverAnswers(client)) return const [];
  final ids = <String>{};
  String? from;
  do {
    final page = await client.getMutualRooms(userId, from: from);
    ids.addAll(page.joined);
    from = page.nextBatch;
  } while (from != null);
  return [
    for (final room in client.rooms)
      if (ids.contains(room.id) &&
          room.id != here.id &&
          isJoinedGroupRoom(room))
        room,
  ]..sort(newestActivityFirst);
}

Future<bool> _serverAnswers(Client client) async {
  final versions = await client.getVersions();
  return versions.unstableFeatures?[_stableFlag] == true ||
      versions.versions.any(_atLeastSpecVersion);
}

bool _atLeastSpecVersion(String version) {
  final match = _versionPattern.firstMatch(version);
  if (match == null) return false;
  final major = int.parse(match[1]!);
  final minor = int.parse(match[2]!);
  return major > _specVersion.major ||
      (major == _specVersion.major && minor >= _specVersion.minor);
}
