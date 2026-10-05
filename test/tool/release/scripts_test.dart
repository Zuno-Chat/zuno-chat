import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final scripts = Directory('tool/release').absolute.path;
  late Directory root;
  late String origin;
  late String work;
  late File ghLog;
  late Map<String, String> env;

  String git(String dir, List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: dir);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return (result.stdout as String).trim();
  }

  void write(String path, String text) => File('$work/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  void commit(String subject) {
    git(work, ['add', '--all']);
    git(work, ['commit', '--allow-empty', '--quiet', '--message', subject]);
  }

  void push([List<String> refs = const ['master']]) =>
      git(work, ['push', '--quiet', 'origin', ...refs]);

  String remote(String ref, String path) => git(origin, ['show', '$ref:$path']);

  String head(String ref) => git(origin, ['rev-parse', ref]);

  Future<ProcessResult> script(
    String name, [
    Map<String, String> extra = const {},
  ]) => Process.run(
    'bash',
    ['$scripts/$name'],
    workingDirectory: work,
    environment: {...env, ...extra},
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('release_scripts');
    origin = '${root.path}/origin.git';
    work = '${root.path}/work';
    ghLog = File('${root.path}/gh.log');
    Directory(work).createSync();
    git(root.path, ['init', '--quiet', '--bare', origin]);
    git(work, ['init', '--quiet', '--initial-branch', 'master']);
    git(work, ['remote', 'add', 'origin', origin]);
    git(work, ['config', 'user.email', 'bot@example.com']);
    git(work, ['config', 'user.name', 'Bot']);
    git(work, ['config', 'commit.gpgsign', 'false']);
    final gh = File('${root.path}/bin/gh')
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho "\$*" >> "${ghLog.path}"\n');
    Process.runSync('chmod', ['+x', gh.path]);
    env = {'PATH': '${gh.parent.path}:${Platform.environment['PATH']}'};
    write('pubspec.yaml', 'name: zuno\nversion: 1.3.0+3\n');
    write('docs/release-notes/next.txt', '');
    write('.github/workflows/release.yml', 'name: release\n');
    commit('chore: start');
    git(work, ['tag', 'v1.3.0']);
    push(['master', 'v1.3.0']);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('cut.sh', () {
    test('cuts a minor release onto master and rc, then dispatches', () async {
      write('docs/release-notes/next.txt', 'Maps in chats.\n');
      commit('feat: maps');
      push();

      final result = await script('cut.sh');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        git(origin, ['log', '-1', '--format=%s', 'master']),
        'chore: release 1.4.0',
      );
      expect(
        remote('master', 'pubspec.yaml'),
        'name: zuno\nversion: 1.4.0+1004000',
      );
      expect(
        remote('master', 'docs/release-notes/1.4.0.txt'),
        'Maps in chats.',
      );
      expect(remote('master', 'docs/release-notes/next.txt'), '');
      expect(head('rc/1.4.0'), head('master'));
      expect(
        ghLog.readAsStringSync(),
        'workflow run release.yml --ref rc/1.4.0\n',
      );
    });

    test('a re-run reuses the cut and dispatches again', () async {
      write('docs/release-notes/next.txt', 'Maps.\n');
      commit('feat: maps');
      push();
      await script('cut.sh');
      final cut = head('master');

      final rerun = await script('cut.sh');

      expect(rerun.exitCode, 0, reason: '${rerun.stderr}');
      expect(head('master'), cut);
      expect(ghLog.readAsLinesSync(), hasLength(2));
    });

    test('a month with only chores cuts nothing', () async {
      commit('chore: tidy');
      push();
      final before = head('master');

      final result = await script('cut.sh');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('nothing to cut'));
      expect(head('master'), before);
      expect(ghLog.existsSync(), isFalse);
    });

    test(
      'empty release notes stop the cut before anything is pushed',
      () async {
        commit('fix: crash');
        push();
        final before = head('master');

        final result = await script('cut.sh');

        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('empty'));
        expect(head('master'), before);
        expect(ghLog.existsSync(), isFalse);
      },
    );

    test('a stale rc branch stops the cut before master moves', () async {
      write('docs/release-notes/next.txt', 'Fixes.\n');
      commit('fix: crash');
      push(['master', 'master:refs/heads/rc/1.3.1']);
      commit('fix: another');
      push();
      final before = head('master');

      final result = await script('cut.sh');

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('rc/1.3.1 exists'));
      expect(head('master'), before);
      expect(ghLog.existsSync(), isFalse);
    });

    test('new notes after an earlier cut stop a re-run', () async {
      write('docs/release-notes/next.txt', 'Maps.\n');
      commit('feat: maps');
      push();
      await script('cut.sh');
      write('docs/release-notes/next.txt', 'Later notes.\n');
      commit('fix: later');

      final rerun = await script('cut.sh');

      expect(rerun.exitCode, isNot(0));
      expect(rerun.stderr, contains('next.txt has new notes'));
    });
  });

  group('hotfix.sh', () {
    test('cherry-picks onto rc/1.3.1 from v1.3.0 and dispatches', () async {
      write('lib/a.txt', 'fixed\n');
      commit('fix: crash');
      push();
      final fix = git(work, ['rev-parse', 'HEAD']);

      final result = await script('hotfix.sh', {
        'COMMITS': fix,
        'NOTES': 'Fixes a crash.',
      });

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(remote('rc/1.3.1', 'lib/a.txt'), 'fixed');
      expect(
        remote('rc/1.3.1', 'pubspec.yaml'),
        'name: zuno\nversion: 1.3.1+1003001',
      );
      expect(
        remote('rc/1.3.1', 'docs/release-notes/1.3.1.txt'),
        'Fixes a crash.',
      );
      expect(
        git(origin, ['log', '-1', '--format=%s', 'rc/1.3.1']),
        'chore: release 1.3.1',
      );
      git(origin, ['merge-base', '--is-ancestor', 'v1.3.0', 'rc/1.3.1']);
      expect(remote('master', 'pubspec.yaml'), 'name: zuno\nversion: 1.3.0+3');
      expect(
        ghLog.readAsStringSync(),
        'workflow run release.yml --ref rc/1.3.1\n',
      );
    });

    test('a fix that also added a notes line still cherry-picks', () async {
      write('docs/release-notes/next.txt', 'Maps.\n');
      commit('feat: maps');
      write('docs/release-notes/next.txt', 'Maps.\nNo more crash on launch.\n');
      write('lib/b.txt', 'fixed\n');
      commit('fix: crash');
      push();
      final fix = git(work, ['rev-parse', 'HEAD']);

      final result = await script('hotfix.sh', {
        'COMMITS': fix,
        'NOTES': 'Fixes a crash.',
      });

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(remote('rc/1.3.1', 'lib/b.txt'), 'fixed');
      expect(remote('rc/1.3.1', 'docs/release-notes/next.txt'), '');
      expect(
        git(origin, ['log', '-1', '--format=%s', 'rc/1.3.1~1']),
        'fix: crash',
      );
      expect(
        git(origin, ['log', '-1', '--format=%B', 'rc/1.3.1~1']),
        contains('(cherry picked from commit $fix)'),
      );
    });

    test('refuses a commit that is not on master', () async {
      git(work, ['switch', '--quiet', '--create', 'side']);
      write('lib/c.txt', 'side\n');
      commit('fix: unmerged');
      final side = git(work, ['rev-parse', 'HEAD']);
      git(work, ['switch', '--quiet', 'master']);

      final result = await script('hotfix.sh', {
        'COMMITS': side,
        'NOTES': 'Fixes.',
      });

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('not on master'));
      expect(git(origin, ['branch', '--list', 'rc/*']), '');
      expect(ghLog.existsSync(), isFalse);
    });

    test('a conflicting fix aborts with nothing pushed', () async {
      write('lib/a.txt', 'one\n');
      commit('chore: add a');
      write('lib/a.txt', 'two\n');
      commit('fix: change a');
      push();

      final result = await script('hotfix.sh', {
        'COMMITS': git(work, ['rev-parse', 'HEAD']),
        'NOTES': 'Fixes.',
      });

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('does not apply cleanly'));
      expect(git(origin, ['branch', '--list', 'rc/*']), '');
      expect(ghLog.existsSync(), isFalse);
    });

    test('refuses a base tag from before the pipeline', () async {
      git(work, ['rm', '--quiet', '.github/workflows/release.yml']);
      commit('chore: drop pipeline');
      git(work, ['tag', 'v1.3.9']);
      push(['master', 'v1.3.9']);

      final result = await script('hotfix.sh', {
        'COMMITS': git(work, ['rev-parse', 'HEAD']),
        'NOTES': 'Fixes.',
      });

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('predates the release pipeline'));
    });

    test('blank notes stop the hotfix', () async {
      commit('fix: crash');
      push();

      final result = await script('hotfix.sh', {
        'COMMITS': git(work, ['rev-parse', 'HEAD']),
        'NOTES': ' ',
      });

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('empty'));
      expect(ghLog.existsSync(), isFalse);
    });
  });
}
