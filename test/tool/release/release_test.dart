import 'package:flutter_test/flutter_test.dart';

import '../../../tool/release/release.dart';

void main() {
  group('Version', () {
    test('parses tags and rc branches', () {
      expect(Version.fromTag('v1.4.0'), const Version(1, 4, 0));
      expect(Version.fromBranch('rc/1.10.2'), const Version(1, 10, 2));
    });

    test('rejects anything that is not exactly X.Y.Z', () {
      for (final tag in [
        'v1.4',
        'v1.4.0-rc1',
        '1.4.0',
        'release-1.4.0',
        'v1.4.0.1',
      ]) {
        expect(Version.fromTag(tag), isNull, reason: tag);
      }
      expect(Version.fromBranch('rc/dry-run'), isNull);
      expect(Version.fromBranch('master'), isNull);
    });

    test('derives the build number from the version', () {
      expect(const Version(1, 4, 1).buildNumber, 1004001);
      expect(const Version(1, 3, 0).buildNumber, 1003000);
      expect(const Version(2, 0, 0).buildNumber, 2000000);
    });

    test('refuses a build number once a part outgrows its digits', () {
      expect(() => const Version(1, 1000, 0).buildNumber, throwsStateError);
      expect(() => const Version(1, 0, 1000).buildNumber, throwsStateError);
      expect(() => const Version(2100, 0, 0).buildNumber, throwsStateError);
    });

    test('formats tag, branch and pubspec version', () {
      const version = Version(1, 4, 1);
      expect(version.tag, 'v1.4.1');
      expect(version.branch, 'rc/1.4.1');
      expect(version.pubspecVersion, '1.4.1+1004001');
    });
  });

  group('highestRelease', () {
    test('compares numerically, not as text', () {
      expect(
        highestRelease(['v1.9.0', 'v1.10.0', 'v1.2.5']),
        const Version(1, 10, 0),
      );
    });

    test('ignores tags that are not releases', () {
      expect(
        highestRelease(['v2.0.0-rc1', 'v1.3.0', 'nightly', '3.0.0']),
        const Version(1, 3, 0),
      );
    });

    test('is null with no release tags', () {
      expect(highestRelease(['nightly']), isNull);
    });
  });

  group('commitTypes', () {
    test('reads every type in a combined subject', () {
      expect(commitTypes('chore: minimum Android 8.0; fix: cache test raced'), {
        'chore',
        'fix',
      });
    });

    test('accepts scopes, breaking marks and capitals', () {
      expect(commitTypes('feat(chat): reactions'), {'feat'});
      expect(commitTypes('fix!: drop legacy store'), {'fix'});
      expect(commitTypes('Fix: crash on launch'), {'fix'});
    });

    test('ignores a type-like word inside the text', () {
      expect(commitTypes('chore: rename the fix: label'), {'chore'});
      expect(commitTypes('Merge branch rc/1.4.1'), isEmpty);
    });
  });

  group('nextRelease', () {
    const latest = Version(1, 4, 2);

    test('a feat makes a minor release and resets the patch', () {
      expect(
        nextRelease(latest, ['fix: a', 'feat: b']),
        const Version(1, 5, 0),
      );
    });

    test('only fixes make a patch release', () {
      expect(
        nextRelease(latest, ['fix: a', 'chore: b']),
        const Version(1, 4, 3),
      );
    });

    test('a combined subject counts its feat', () {
      expect(
        nextRelease(latest, ['chore: tidy; feat: maps']),
        const Version(1, 5, 0),
      );
    });

    test('nothing user-facing means no release', () {
      expect(
        nextRelease(latest, ['chore: release 1.4.2', 'docs: x', 'test: y']),
        isNull,
      );
      expect(nextRelease(latest, []), isNull);
    });
  });

  group('cherryPickSources', () {
    test('reads every cherry-pick trailer as a full commit hash', () {
      const a = '1111111111111111111111111111111111111111';
      const b = '2222222222222222222222222222222222222222';
      expect(
        cherryPickSources(
          'fix: crash\n\n(cherry picked from commit $a)\n'
          'chore: release 1.4.1\n'
          'fix: other\n\n(cherry picked from commit $b)\n',
        ),
        {a, b},
      );
    });

    test('ignores messages without a trailer', () {
      expect(cherryPickSources('fix: crash\n\nnot cherry picked\n'), isEmpty);
    });
  });

  group('notesProblem', () {
    test('accepts notes up to 500 characters', () {
      expect(notesProblem('Calls ring on the lock screen.\n'), isNull);
      expect(notesProblem('a' * 500), isNull);
    });

    test('rejects empty or whitespace-only notes', () {
      expect(notesProblem(''), contains('empty'));
      expect(notesProblem(' \r\n\n'), contains('empty'));
    });

    test('rejects notes over 500 characters', () {
      expect(notesProblem('a' * 501), contains('501'));
    });

    test('counts characters, not code units or CRLF bytes', () {
      expect(notesProblem('${'🎉' * 500}\r\n'), isNull);
      expect(notesProblem(List.filled(250, 'a').join('\r\n')), isNull);
    });
  });

  group('pubspec version', () {
    const pubspec =
        'name: zuno\nversion: 1.3.0+3\n\ndependencies:\n'
        '  foo:\n    version: ^1.0.0\n';

    test('reads the top-level version', () {
      expect(pubspecVersion(pubspec), '1.3.0+3');
    });

    test('rewrites only the top-level version line', () {
      expect(
        withPubspecVersion(pubspec, const Version(1, 4, 0)),
        'name: zuno\nversion: 1.4.0+1004000\n\ndependencies:\n'
        '  foo:\n    version: ^1.0.0\n',
      );
    });

    test('rewrites a version without a build number or with a comment', () {
      expect(
        withPubspecVersion('version: 1.3.0 # old\n', const Version(1, 3, 1)),
        'version: 1.3.1+1003001\n',
      );
    });

    test('refuses a pubspec with no version line', () {
      expect(
        () => withPubspecVersion('name: zuno\n', const Version(1, 4, 0)),
        throwsFormatException,
      );
    });
  });

  group('releaseProblem', () {
    const tags = ['v1.3.0', 'v1.4.0'];
    String pubspecFor(String version) => 'name: zuno\nversion: $version\n';

    test('passes a new version above the latest with a matching pubspec', () {
      expect(
        releaseProblem(
          version: const Version(1, 4, 1),
          tags: tags,
          pubspec: pubspecFor('1.4.1+1004001'),
        ),
        isNull,
      );
    });

    test('blocks a version that already has a tag', () {
      expect(
        releaseProblem(
          version: const Version(1, 4, 0),
          tags: tags,
          pubspec: pubspecFor('1.4.0+1004000'),
        ),
        contains('already exists'),
      );
    });

    test('blocks a version at or below the latest release', () {
      expect(
        releaseProblem(
          version: const Version(1, 3, 1),
          tags: tags,
          pubspec: pubspecFor('1.3.1+1003001'),
        ),
        contains('not above'),
      );
    });

    test('blocks a pubspec that does not match the branch', () {
      expect(
        releaseProblem(
          version: const Version(1, 4, 1),
          tags: tags,
          pubspec: pubspecFor('1.4.0+1004000'),
        ),
        contains('expected 1.4.1+1004001'),
      );
    });
  });

  group('nextRolloutFraction', () {
    test('climbs the phased ladder one step at a time', () {
      expect(nextRolloutFraction('inProgress', 0.01), 0.02);
      expect(nextRolloutFraction('inProgress', 0.2), 0.5);
      expect(nextRolloutFraction('inProgress', 0.5), 1.0);
    });

    test('moves a hand-set fraction to the next step above it', () {
      expect(nextRolloutFraction('inProgress', 0.3), 0.5);
    });

    test('leaves halted, completed and absent releases alone', () {
      expect(nextRolloutFraction('halted', 0.05), isNull);
      expect(nextRolloutFraction('completed', 1.0), isNull);
      expect(nextRolloutFraction('none', 0), isNull);
    });

    test('stops at full rollout', () {
      expect(nextRolloutFraction('inProgress', 1.0), isNull);
    });
  });
}
