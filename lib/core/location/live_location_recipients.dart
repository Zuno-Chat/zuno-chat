import 'package:matrix/matrix.dart';

const _unreachableFor = Duration(minutes: 30);

bool isLiveLocationPeer(
  Room room,
  DeviceKeys device, {
  required Set<String> ignored,
}) {
  final client = room.client;
  final userId = device.userId;
  if (userId == client.userID && device.deviceId == client.deviceID) {
    return false;
  }
  if (ignored.contains(userId)) return false;
  final member = room.getState(EventTypes.RoomMember, userId);
  if (member?.content['membership'] != Membership.join.name) return false;
  final current = client.userDeviceKeys[userId]?.deviceKeys[device.deviceId];
  return current != null && current.encryptToDevice;
}

Future<List<DeviceKeys>> liveLocationRecipients(Room room) async {
  final client = room.client;
  final members = await room.requestParticipants(
    const [Membership.join],
    true,
    true,
  );
  final joined = {for (final member in members) member.id};
  final untracked = joined
      .where((userId) => client.userDeviceKeys[userId] == null)
      .toSet();
  if (untracked.isNotEmpty) {
    await client.updateUserDeviceKeys(additionalUsers: untracked);
  }
  final ignored = client.ignoredUsers.toSet();
  return [
    for (final userId in joined)
      for (final device in [
        ...?client.userDeviceKeys[userId]?.deviceKeys.values,
      ])
        if (isLiveLocationPeer(room, device, ignored: ignored)) device,
  ];
}

class UnreachableDevices {
  UnreachableDevices(this._client);

  final Client _client;
  final _until = <String, DateTime>{};

  bool contains(DeviceKeys device, DateTime now) {
    final key = _keyOf(device);
    final until = _until[key];
    if (until == null) return false;
    if (now.isBefore(until) && until.difference(now) <= _unreachableFor) {
      return true;
    }
    _until.remove(key);
    return false;
  }

  void noteWithoutSession(List<DeviceKeys> devices, DateTime now) {
    final sessions = _client.encryption?.olmManager.olmSessions;
    if (sessions == null) return;
    for (final device in devices) {
      final curve = device.curve25519Key;
      if (curve == null || (sessions[curve]?.isNotEmpty ?? false)) continue;
      _until[_keyOf(device)] = now.add(_unreachableFor);
    }
  }

  void forgetUsers(Set<String> userIds) =>
      _until.removeWhere((key, _) => userIds.contains(key.split('|').first));

  static String _keyOf(DeviceKeys device) =>
      '${device.userId}|${device.deviceId}';
}
