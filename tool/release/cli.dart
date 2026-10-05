import 'dart:convert';
import 'dart:io';

import 'release.dart';

void main(List<String> args) {
  try {
    final output = run(args, Directory.current.path);
    if (output != null) stdout.writeln(output);
  } on ReleaseFailure catch (failure) {
    _fail(failure.message);
  } on FormatException catch (error) {
    _fail(error.message);
  } on StateError catch (error) {
    _fail(error.message);
  }
}

void _fail(String message) {
  stderr.writeln('release: $message');
  exitCode = 1;
}

final class ReleaseFailure implements Exception {
  const ReleaseFailure(this.message);

  final String message;
}

String? run(List<String> args, String root) => switch (args) {
  ['next'] => _next(root)?.toString() ?? 'none',
  ['hotfix'] => _hotfix(root),
  ['guard', '--dry-run', final branch] => _dryRunVersion(root, branch),
  ['guard', final branch] => _guard(root, branch),
  ['build-number', final version] => '${_parse(version).buildNumber}',
  ['bump', final version] => _bump(root, _parse(version)),
  ['check-notes', final path] => _checkNotes(path),
  ['rollout', final status, final fraction] => _rollout(status, fraction),
  _ => throw const ReleaseFailure(
    'usage: next | hotfix | guard [--dry-run] <branch> | '
    'build-number <X.Y.Z> | bump <X.Y.Z> | check-notes <file> | '
    'rollout <status> <fraction>',
  ),
};

String _git(String root, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw ReleaseFailure('git ${args.join(' ')}: ${result.stderr}'.trim());
  }
  return result.stdout as String;
}

List<String> _gitLines(String root, List<String> args) =>
    const LineSplitter().convert(_git(root, args));

List<String> _tags(String root) => _gitLines(root, ['tag', '--list', 'v*']);

Version _latest(String root) =>
    highestRelease(_tags(root)) ??
    (throw const ReleaseFailure('no vX.Y.Z tag; tag the last release first'));

Version? _next(String root) {
  final latest = _latest(root);
  final shipped = cherryPickSources(
    _git(root, ['log', '--format=%B', 'HEAD..${latest.tag}']),
  );
  final unreleased = _gitLines(root, [
    'log',
    '--format=%H %s',
    '${latest.tag}..HEAD',
  ]);
  final subjects = [
    for (final line in unreleased)
      if (!shipped.contains(line.substring(0, 40))) line.substring(41),
  ];
  return nextRelease(latest, subjects);
}

String _hotfix(String root) {
  final latest = _latest(root);
  return '${latest.nextPatch()} ${latest.tag}';
}

String _dryRunVersion(String root, String branch) {
  if (branch != 'rc/dry-run') {
    throw ReleaseFailure('a dry run runs on rc/dry-run only, not $branch');
  }
  return '${_next(root) ?? _latest(root).nextPatch()}';
}

String _guard(String root, String branch) {
  final version =
      Version.fromBranch(branch) ??
      (throw ReleaseFailure('$branch is not an rc/X.Y.Z branch'));
  final problem = releaseProblem(
    version: version,
    tags: _tags(root),
    pubspec: File('$root/pubspec.yaml').readAsStringSync(),
  );
  if (problem != null) throw ReleaseFailure(problem);
  _checkNotes('$root/docs/release-notes/$version.txt');
  return '$version';
}

Version _parse(String text) =>
    Version.tryParse(text) ?? (throw ReleaseFailure('$text is not X.Y.Z'));

String? _bump(String root, Version version) {
  final pubspec = File('$root/pubspec.yaml');
  pubspec.writeAsStringSync(
    withPubspecVersion(pubspec.readAsStringSync(), version),
  );
  return null;
}

String? _checkNotes(String path) {
  final file = File(path);
  if (!file.existsSync()) throw ReleaseFailure('$path is missing');
  final problem = notesProblem(file.readAsStringSync());
  if (problem != null) throw ReleaseFailure('$path: $problem');
  return null;
}

String _rollout(String status, String fraction) {
  final value =
      double.tryParse(fraction) ??
      (throw ReleaseFailure('$fraction is not a fraction'));
  return nextRolloutFraction(status, value)?.toString() ?? 'none';
}
