import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/password_strength.dart';

void main() {
  group('what is blocked', () {
    test('anything under 12 characters', () {
      final assessment = assessPassword('gk7wqz2mvp4');
      expect(assessment.isUsable, isFalse);
      expect(assessment.blocker, contains('12'));
    });

    test('12 characters clears the floor', () {
      expect(assessPassword('gk7wqz2mvp4x').isUsable, isTrue);
    });

    test('a password on the known-bad list, whatever its case', () {
      expect(assessPassword('password1234').isUsable, isFalse);
      expect(assessPassword('PassWord1234').isUsable, isFalse);
    });

    test('one repeated character, or a straight run', () {
      expect(assessPassword('aaaaaaaaaaaa').isUsable, isFalse);
      expect(assessPassword('abcdefghijkl').isUsable, isFalse);
      expect(assessPassword('lkjihgfedcba').isUsable, isFalse);
      expect(assessPassword('abcabcabcabc').isUsable, isFalse);
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
        expect(assessPassword(password).isUsable, isFalse, reason: password);
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
        expect(assessPassword(password).isUsable, isFalse, reason: password);
      }
    });

    test('two known-bad passwords joined together', () {
      for (final password in ['password password', 'iloveyou-password']) {
        expect(assessPassword(password).isUsable, isFalse, reason: password);
      }
    });

    test('characters are counted the way the homeserver counts them', () {
      final assessment = assessPassword('😀🙃😀🙃😀🙃');
      expect(assessment.isUsable, isFalse);
      expect(assessment.blocker, contains('12'));
    });

    test('says the padding is the problem, not the length', () {
      expect(assessPassword('password12345').blocker, contains('common'));
    });

    test('the username reused as the password', () {
      expect(
        assessPassword(
          'alexanderthegreat',
          username: 'alexanderthegreat',
        ).isUsable,
        isFalse,
      );
      expect(
        assessPassword('alexander991', username: 'alexander').isUsable,
        isFalse,
      );
    });

    test('says which problem it is, not a generic one', () {
      expect(
        assessPassword(
          'alexanderthegreat',
          username: 'alexanderthegreat',
        ).blocker,
        contains('username'),
      );
      expect(
        assessPassword('myalexander1', username: 'alexander').blocker,
        contains('username'),
      );
    });

    test('the username check wins over the common-password list', () {
      expect(
        assessPassword('password1234', username: 'password1234').blocker,
        contains('username'),
      );
    });

    test('a short username is not matched inside a password', () {
      expect(assessPassword('kebobsalad42', username: 'bob').isUsable, isTrue);
    });

    test('nothing typed yet is not an error', () {
      final assessment = assessPassword('');
      expect(assessment.blocker, isNull);
      expect(assessment.advice, isNotEmpty);
    });
  });

  group('what is allowed through', () {
    test('a weak but unguessable password is advice, not a refusal', () {
      final assessment = assessPassword('mississippis');
      expect(assessment.isUsable, isTrue);
      expect(assessment.strength, PasswordStrength.weak);
    });

    test('a long passphrase with no symbols at all rates strong', () {
      final assessment = assessPassword('correct battery staple mountain');
      expect(assessment.strength, PasswordStrength.strong);
      expect(assessment.isUsable, isTrue);
    });

    test('a common word inside something longer is allowed', () {
      expect(assessPassword('mydogsummer2026').isUsable, isTrue);
      expect(assessPassword('correct-horse-summer').isUsable, isTrue);
    });

    test('a passphrase of everyday words is advice, not a refusal', () {
      for (final password in [
        'hello sunshine princess',
        'summer family chocolate',
      ]) {
        final assessment = assessPassword(password);
        expect(assessment.isUsable, isTrue, reason: password);
        expect(assessment.strength, PasswordStrength.weak, reason: password);
      }
    });

    test('random digits are not mistaken for a run', () {
      expect(assessPassword('839205746152').isUsable, isTrue);
    });

    test('spaces are ordinary characters', () {
      expect(assessPassword('a quiet blue harbour').isUsable, isTrue);
    });
  });

  group('the meter', () {
    test('rises with length', () {
      final short = assessPassword('Tr0ub4dRTr0u');
      final long = assessPassword('Tr0ub4dRTr0ub4dRxyz');
      expect(short.strength.index, lessThan(long.strength.index));
    });

    test('scores only what is left once the guessable part is gone', () {
      expect(assessPassword('mydogsummer2026').strength, PasswordStrength.weak);
      expect(
        assessPassword('password-Kx7#m').strength.index,
        lessThan(assessPassword('gvrbtnhw-Kx7#m').strength.index),
      );
    });

    test('advice counts characters the way the floor does', () {
      final assessment = assessPassword('amzmazzamaz😀😀');

      expect(assessment.strength, PasswordStrength.fair);
      expect(assessment.advice, contains('A few more characters'));
    });

    test('does not reward repetition', () {
      final varied = assessPassword('gk7wqz2mvp4x');
      final repetitive = assessPassword('aaaaaaaaaaab');
      expect(
        repetitive.strength.index,
        lessThanOrEqualTo(varied.strength.index),
      );
    });
  });

  test('the recommended length is above the enforced one', () {
    expect(recommendedPasswordLength, greaterThan(minPasswordLength));
  });
}
