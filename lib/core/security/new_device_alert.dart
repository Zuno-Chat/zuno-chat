class NewDeviceAlert {
  final String deviceId;
  final String? displayName;

  const NewDeviceAlert({required this.deviceId, this.displayName});

  String get label {
    final name = displayName?.trim() ?? '';
    return name.isEmpty ? deviceId : name;
  }

  @override
  bool operator ==(Object other) =>
      other is NewDeviceAlert &&
      other.deviceId == deviceId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(deviceId, displayName);
}

List<NewDeviceAlert> newDeviceAlerts({
  required Set<String>? knownDeviceIds,
  required Map<String, String?> currentDevices,
  required String? ownDeviceId,
}) {
  if (knownDeviceIds == null) return const [];
  return [
    for (final entry in currentDevices.entries)
      if (entry.key != ownDeviceId && !knownDeviceIds.contains(entry.key))
        NewDeviceAlert(deviceId: entry.key, displayName: entry.value),
  ];
}

({String title, String body}) newDeviceNotificationText(NewDeviceAlert alert) =>
    (
      title: 'New sign-in',
      body:
          '${alert.label} just signed in to your account. If that was not you, '
          'sign it out now.',
    );
