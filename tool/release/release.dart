final class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  static Version? tryParse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return Version(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  static Version? fromTag(String tag) =>
      tag.startsWith('v') ? tryParse(tag.substring(1)) : null;

  static Version? fromBranch(String branch) =>
      branch.startsWith('rc/') ? tryParse(branch.substring(3)) : null;

  Version nextMinor() => Version(major, minor + 1, 0);

  Version nextPatch() => Version(major, minor, patch + 1);

  int get buildNumber {
    if (major > 2099 || minor > 999 || patch > 999) {
      throw StateError(
        '$this has no build number: MAJOR must stay at or below 2099, '
        'MINOR and PATCH at or below 999',
      );
    }
    return major * 1000000 + minor * 1000 + patch;
  }

  String get tag => 'v$this';

  String get branch => 'rc/$this';

  String get pubspecVersion => '$this+$buildNumber';

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is Version &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

final _commitType = RegExp(
  r'(?:^|;\s*)([a-z]+)(?:\([^)]*\))?!?:',
  caseSensitive: false,
);

Set<String> commitTypes(String subject) => {
  for (final match in _commitType.allMatches(subject)) match[1]!.toLowerCase(),
};

Version? highestRelease(Iterable<String> tags) {
  Version? highest;
  for (final version in tags.map(Version.fromTag).nonNulls) {
    if (highest == null || version.compareTo(highest) > 0) highest = version;
  }
  return highest;
}

Version? nextRelease(Version latest, Iterable<String> subjects) {
  final types = subjects.expand(commitTypes).toSet();
  if (types.contains('feat')) return latest.nextMinor();
  if (types.contains('fix')) return latest.nextPatch();
  return null;
}

final _cherryPickTrailer = RegExp(
  r'\(cherry picked from commit ([0-9a-f]{40})\)',
);

Set<String> cherryPickSources(String messages) => {
  for (final match in _cherryPickTrailer.allMatches(messages)) match[1]!,
};

const maxNotesLength = 500;

String? notesProblem(String notes) {
  final text = notes.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return 'the release notes are empty';
  final length = text.runes.length;
  if (length > maxNotesLength) {
    return 'the release notes are $length characters; '
        'Play allows $maxNotesLength';
  }
  return null;
}

final _versionLine = RegExp(r'^version:[ \t]*(\S*).*$', multiLine: true);

String? pubspecVersion(String pubspec) => _versionLine.firstMatch(pubspec)?[1];

String withPubspecVersion(String pubspec, Version version) {
  if (!_versionLine.hasMatch(pubspec)) {
    throw const FormatException('pubspec.yaml has no top-level version line');
  }
  return pubspec.replaceFirst(
    _versionLine,
    'version: ${version.pubspecVersion}',
  );
}

String? releaseProblem({
  required Version version,
  required Iterable<String> tags,
  required String pubspec,
}) {
  final tagList = tags.toList();
  if (tagList.contains(version.tag)) {
    return '${version.tag} already exists, so $version has shipped';
  }
  final latest = highestRelease(tagList);
  if (latest != null && version.compareTo(latest) <= 0) {
    return '$version is not above the latest release, $latest; '
        'the App Store rejects a lower version';
  }
  final declared = pubspecVersion(pubspec);
  if (declared != version.pubspecVersion) {
    return 'pubspec.yaml declares $declared, '
        'expected ${version.pubspecVersion}';
  }
  return null;
}

const rolloutLadder = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0];

double? nextRolloutFraction(String status, double fraction) {
  if (status != 'inProgress') return null;
  for (final step in rolloutLadder) {
    if (step > fraction + 1e-9) return step;
  }
  return null;
}
