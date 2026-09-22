const knownRemoteTrackNames = {'audio', 'video'};

List<String> planRemoteTracks({
  required Iterable<String> advertised,
  required Set<String> pulled,
  required bool remoteVideoEnabled,
  required bool remoteEncrypted,
  required bool localEncrypted,
}) {
  if (!localEncrypted || !remoteEncrypted) return const [];
  return [
    for (final name in advertised)
      if (knownRemoteTrackNames.contains(name) &&
          !pulled.contains(name) &&
          (name != 'video' || remoteVideoEnabled))
        name,
  ];
}
