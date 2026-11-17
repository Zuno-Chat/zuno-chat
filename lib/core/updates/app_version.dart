final _release = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

int? buildNumberOf(String version) {
  final match = _release.firstMatch(version);
  if (match == null) return null;
  final [major, minor, patch] = [
    for (var group = 1; group <= 3; group++) int.parse(match.group(group)!),
  ];
  if (minor > 999 || patch > 999) return null;
  return major * 1000000 + minor * 1000 + patch;
}

String versionOfBuild(int build) =>
    '${build ~/ 1000000}.${build ~/ 1000 % 1000}.${build % 1000}';
