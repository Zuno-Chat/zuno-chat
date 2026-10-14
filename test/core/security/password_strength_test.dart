import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/password_strength.dart';

void main() {
  PasswordAssessment assess(String password, {String? username}) =>
      assessPassword(englishLocalizations, password, username: username);

  group('what is blocked', () {
    test('anything under 12 characters', () {
      final assessment = assess('gk7wqz2mvp4');
      expect(assessment.isUsable, isFalse);
      expect(assessment.blocker, contains('12'));
    });

    test('12 characters clears the floor', () {
      expect(assess('gk7wqz2mvp4x').isUsable, isTrue);
    });

    test('a password on the known-bad list, whatever its case', () {
      expect(assess('password1234').isUsable, isFalse);
      expect(assess('PassWord1234').isUsable, isFalse);
    });

    test('one repeated character, or a straight run', () {
      expect(assess('aaaaaaaaaaaa').isUsable, isFalse);
      expect(assess('abcdefghijkl').isUsable, isFalse);
      expect(assess('lkjihgfedcba').isUsable, isFalse);
      expect(assess('abcabcabcabc').isUsable, isFalse);
    });

    test('a known-bad password padded out to the floor', () {
      for (final password in [
        'password12345',
        'iloveyou1234',
        'qwertyuiop123',
        'Password2026!',
        'summer2026!!',
        'welcome12345',
        'letmein!@#\$%',
        'zunochat2026',
        'October2025!',
      ]) {
        expect(assess(password).isUsable, isFalse, reason: password);
      }
    });

    test('runs and keyboard walks stitched together', () {
      for (final password in [
        '123456789012',
        'qwertyuiop[]',
        '1q2w3e4r5t6y',
        'asdfghjkl123',
        'aaaabbbbcccc',
      ]) {
        expect(assess(password).isUsable, isFalse, reason: password);
      }
    });

    test('two known-bad passwords joined together', () {
      for (final password in ['password password', 'iloveyou-password']) {
        expect(assess(password).isUsable, isFalse, reason: password);
      }
    });

    test('characters are counted the way the homeserver counts them', () {
      final assessment = assess('😀🙃😀🙃😀🙃');
      expect(assessment.isUsable, isFalse);
      expect(assessment.blocker, contains('12'));
    });

    test('says the padding is the problem, not the length', () {
      expect(assess('password12345').blocker, contains('common'));
    });

    test('the username, whole or inside the password, is named as the '
        'problem', () {
      expect(
        assess('alexanderthegreat', username: 'alexanderthegreat').blocker,
        contains('username'),
      );
      expect(
        assess('myalexander1', username: 'alexander').blocker,
        contains('username'),
      );
    });

    test('the username check wins over the common-password list', () {
      expect(
        assess('password1234', username: 'password1234').blocker,
        contains('username'),
      );
    });

    test('a short username is not matched inside a password', () {
      expect(assess('kebobsalad42', username: 'bob').isUsable, isTrue);
    });

    test('nothing typed yet is not an error', () {
      final assessment = assess('');
      expect(assessment.blocker, isNull);
      expect(assessment.advice, isNotEmpty);
    });
  });

  group('what is allowed through', () {
    test('a weak but unguessable password is advice, not a refusal', () {
      final assessment = assess('mississippis');
      expect(assessment.isUsable, isTrue);
      expect(assessment.strength, PasswordStrength.weak);
    });

    test('a long passphrase with no symbols at all rates strong', () {
      final assessment = assess('correct battery staple mountain');
      expect(assessment.strength, PasswordStrength.strong);
      expect(assessment.isUsable, isTrue);
    });

    test('a common word inside something longer is allowed', () {
      expect(assess('mydogsummer2026').isUsable, isTrue);
      expect(assess('correct-horse-summer').isUsable, isTrue);
    });

    test('a passphrase of everyday words is advice, not a refusal', () {
      for (final password in [
        'hello sunshine princess',
        'summer family chocolate',
      ]) {
        final assessment = assess(password);
        expect(assessment.isUsable, isTrue, reason: password);
        expect(assessment.strength, PasswordStrength.weak, reason: password);
      }
    });

    test('random digits are not mistaken for a run', () {
      expect(assess('839205746152').isUsable, isTrue);
    });

    test('spaces are ordinary characters', () {
      expect(assess('a quiet blue harbour').isUsable, isTrue);
    });
  });

  group('the meter', () {
    test('rises with length', () {
      final short = assess('Tr0ub4dRTr0u');
      final long = assess('Tr0ub4dRTr0ub4dRxyz');
      expect(short.strength.index, lessThan(long.strength.index));
    });

    test('scores only what is left once the guessable part is gone', () {
      expect(assess('mydogsummer2026').strength, PasswordStrength.weak);
      expect(
        assess('password-Kx7#m').strength.index,
        lessThan(assess('gvrbtnhw-Kx7#m').strength.index),
      );
    });

    test('under the floor, advice counts the characters still to go', () {
      expect(assess('gk7wqz2mvp4').advice, '1 more character to go.');
      expect(assess('gk7').advice, '9 more characters to go.');
    });

    test('advice counts characters the way the floor does', () {
      final assessment = assess('amzmazzamaz😀😀');

      expect(assessment.strength, PasswordStrength.fair);
      expect(assessment.advice, contains('A few more characters'));
    });

    test('does not reward repetition', () {
      final varied = assess('gk7wqz2mvp4x');
      final repetitive = assess('aaaaaaaaaaab');
      expect(
        repetitive.strength.index,
        lessThanOrEqualTo(varied.strength.index),
      );
    });
  });
}
