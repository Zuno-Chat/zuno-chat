import '../media/call_connection.dart';

MediaKind? mediaKindOf(String trackName) =>
    MediaKind.values.asNameMap()[trackName];

List<String> planRemoteTracks({
  required Iterable<String> advertised,
  required Set<String> pulled,
  required Set<MediaKind> wanted,
}) => [
  for (final name in advertised)
    if (!pulled.contains(name) && wanted.contains(mediaKindOf(name))) name,
];
