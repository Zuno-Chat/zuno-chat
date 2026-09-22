class DeviceSessionInfo {
  final String deviceId;
  final String? displayName;
  final bool verified;
  final bool isCurrent;
  final DateTime? lastActivity;
  final String? ipAddress;

  const DeviceSessionInfo({
    required this.deviceId,
    required this.displayName,
    required this.verified,
    required this.isCurrent,
    required this.lastActivity,
    required this.ipAddress,
  });
}

enum SessionApproval { approved, notApproved, unknown }

SessionApproval sessionApproval({
  required bool isCurrent,
  required bool verified,
  required bool? thisDeviceHasIdentityKeys,
}) {
  if (thisDeviceHasIdentityKeys == null) return SessionApproval.unknown;
  if (isCurrent) {
    return thisDeviceHasIdentityKeys
        ? SessionApproval.approved
        : SessionApproval.notApproved;
  }
  if (!thisDeviceHasIdentityKeys) return SessionApproval.unknown;
  return verified ? SessionApproval.approved : SessionApproval.notApproved;
}

List<DeviceSessionInfo> mergeSessionInfo({
  required List<({String deviceId, String? displayName, bool verified})>
  deviceKeys,
  required List<
    ({
      String deviceId,
      String? displayName,
      int? lastSeenTs,
      String? lastSeenIp,
    })
  >
  devices,
  required String? currentDeviceId,
}) {
  final byId = <String, DeviceSessionInfo>{};
  for (final d in deviceKeys) {
    byId[d.deviceId] = DeviceSessionInfo(
      deviceId: d.deviceId,
      displayName: d.displayName,
      verified: d.verified,
      isCurrent: d.deviceId == currentDeviceId,
      lastActivity: null,
      ipAddress: null,
    );
  }
  for (final d in devices) {
    final existing = byId[d.deviceId];
    byId[d.deviceId] = DeviceSessionInfo(
      deviceId: d.deviceId,
      displayName: d.displayName ?? existing?.displayName,
      verified: existing?.verified ?? false,
      isCurrent: d.deviceId == currentDeviceId,
      lastActivity: d.lastSeenTs != null
          ? DateTime.fromMillisecondsSinceEpoch(d.lastSeenTs!)
          : null,
      ipAddress: d.lastSeenIp,
    );
  }

  final sessions = byId.values.toList()
    ..sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      final aTime = a.lastActivity;
      final bTime = b.lastActivity;
      if (aTime == null && bTime == null) {
        return a.deviceId.compareTo(b.deviceId);
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final cmp = bTime.compareTo(aTime);
      return cmp != 0 ? cmp : a.deviceId.compareTo(b.deviceId);
    });
  return sessions;
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatLastActivity(DateTime? time) {
  if (time == null) return 'Unknown';
  final local = time.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final period = local.hour < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year} at $hour12:$minute $period';
}
