import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/recovery_code.dart';
import 'package:zuno/core/security/recovery_code_leak.dart';

RecoveryWordlist _shippedWordlist() => RecoveryWordlist.parse(
  File('assets/wordlist/recovery_words.txt').readAsStringSync(),
);

void main() {
  late RecoveryWordlist list;

  setUp(() => list = _shippedWordlist());

  String code() => list.words.take(recoveryCodeWordCount).join(' ');

  test('a whole recovery code is recognised', () {
    expect(messageRevealsRecoveryCode(code(), list), isTrue);
  });

  test('a recovery code buried in a sentence is recognised', () {
    expect(
      messageRevealsRecoveryCode('sure, here it is: ${code()} thanks', list),
      isTrue,
    );
  });

  test('a pasted security key is recognised', () {
    expect(
      messageRevealsRecoveryCode(
        'EsTc 5dx7 9kQm 2Vbn 4ZpR 7cWy 3TnA 8fHs 6uXj 5rLd 2mKe 9bTq',
        list,
      ),
      isTrue,
    );
  });

  test('an ordinary message is not', () {
    expect(
      messageRevealsRecoveryCode(
        'meet me at the abbey above the harbor around seven',
        list,
      ),
      isFalse,
    );
  });

  test('a few words from the list in a row are not', () {
    expect(
      messageRevealsRecoveryCode(list.words.take(9).join(' '), list),
      isFalse,
    );
  });

  test('a long link is not', () {
    expect(
      messageRevealsRecoveryCode(
        'look at https://example.org/a/VeryLongPathSegment01234567890123456789',
        list,
      ),
      isFalse,
    );
  });
}
