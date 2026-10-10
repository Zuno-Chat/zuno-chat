import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final cli = File('tool/release/cli.dart').absolute.path;
  late Directory repo;

  String git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: repo.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).trim();
  }

  void commit(String subject) =>
      git(['commit', '--allow-empty', '--quiet', '--message', subject]);

  Future<ProcessResult> release(List<String> args) =>
      Process.run('dart', [cli, ...args], workingDirectory: repo.path);

  String pubspec() => File('${repo.path}/pubspec.yaml').readAsStringSync();

  setUp(() {
    repo = Directory.systemTemp.createTempSync('release_cli');
    git(['init', '--quiet', '--initial-branch', 'master']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'Test']);
    git(['config', 'commit.gpgsign', 'false']);
    File('${repo.path}/pubspec.yaml')
        .writeAsStringSync('name: zuno\nversion: 1.3.0+3\n');
    git(['add', '.']);
    commit('chore: start');
    git(['tag', 'v1.3.0']);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  test('next counts master only after the cut, past a hotfix tag', () async {
    commit('feat: maps');
    git(['tag', 'v1.4.0']);
    git(['switch', '--quiet', '--create', 'rc/1.4.1']);
    commit('fix: hotfix');
    git(['tag', 'v1.4.1']);
    git(['switch', '--quiet', 'master']);
    commit('chore: tidy');
    expect((await release(['next'])).stdout, 'none\n');
    commit('fix: later');
    expect((await release(['next'])).stdout, '1.4.2\n');
  });

  test('next skips master fixes that already shipped in a hotfix', () async {
    commit('feat: maps');
    git(['tag', 'v1.4.0']);
    commit('fix: crash');
    final fix = git(['rev-parse', 'HEAD']);
    commit('docs: tidy');
    git(['switch', '--quiet', '--create', 'rc/1.4.1', 'v1.4.0']);
    git(['cherry-pick', '-x', '--allow-empty', fix]);
    git(['tag', 'v1.4.1']);
    git(['switch', '--quiet', 'master']);
    expect((await release(['next'])).stdout, 'none\n');
    commit('fix: later');
    expect((await release(['next'])).stdout, '1.4.2\n');
  });

  test('hotfix names the next patch and its base tag', () async {
    expect((await release(['hotfix'])).stdout, '1.3.1 v1.3.0\n');
  });

  test('bump rewrites the pubspec version', () async {
    final result = await release(['bump', '1.4.0']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(pubspec(), 'name: zuno\nversion: 1.4.0+1004000\n');
  });

  test('guard passes a ready release branch and prints its version', () async {
    await release(['bump', '1.3.1']);
    File('${repo.path}/docs/release-notes/1.3.1.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('Fixes a crash.\n');
    final result = await release(['guard', 'rc/1.3.1']);
    expect(result.stdout, '1.3.1\n', reason: '${result.stderr}');
  });

  test('guard fails a branch whose notes are missing', () async {
    await release(['bump', '1.3.1']);
    final result = await release(['guard', 'rc/1.3.1']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('docs/release-notes/1.3.1.txt is missing'));
  });

  test('guard fails a branch that is not rc/X.Y.Z', () async {
    final result = await release(['guard', 'master']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('not an rc/X.Y.Z branch'));
  });

  test('a dry run refuses any branch but rc/dry-run', () async {
    expect((await release(['guard', '--dry-run', 'rc/1.3.1'])).exitCode, 1);
    commit('fix: a');
    expect(
      (await release(['guard', '--dry-run', 'rc/dry-run'])).stdout,
      '1.3.1\n',
    );
  });

  test('fails without any release tag', () async {
    git(['tag', '--delete', 'v1.3.0']);
    final result = await release(['next']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('no vX.Y.Z tag'));
  });

  test('rollout prints the next step or none', () async {
    expect((await release(['rollout', 'inProgress', '0.05'])).stdout, '0.1\n');
    expect((await release(['rollout', 'halted', '0.05'])).stdout, 'none\n');
  });
}
