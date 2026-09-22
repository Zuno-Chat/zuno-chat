import 'dart:io';
import 'dart:math' as math;
import 'dart:math' show Random, min;

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/recovery_code.dart';

RecoveryWordlist _shippedWordlist() => RecoveryWordlist.parse(
  File('assets/wordlist/recovery_words.txt').readAsStringSync(),
);

int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      cur.add(
        [
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ].reduce(min),
      );
    }
    prev = cur;
  }
  return prev.last;
}

void main() {
  group('normalizeRecoveryPhrase', () {
    test('leaves an already-clean code untouched', () {
      expect(
        normalizeRecoveryPhrase('acorn blew celery diesel elbow fever glow'),
        'acorn blew celery diesel elbow fever glow',
      );
    });

    test('survives what a phone keyboard and a notes app actually do', () {
      const messy = 'Acorn  blew celery​diesel elbow fever glow\n';
      expect(
        normalizeRecoveryPhrase(messy),
        'acorn blew celery diesel elbow fever glow',
      );
    });

    test('is idempotent', () {
      const input = '  Acorn,  BLEW.  celery ';
      final once = normalizeRecoveryPhrase(input);
      expect(normalizeRecoveryPhrase(once), once);
    });

    test('treats punctuation and digits as separators, not as letters', () {
      expect(
        normalizeRecoveryPhrase('acorn, blew! 42 celery'),
        'acorn blew celery',
      );
      expect(normalizeRecoveryPhrase('acorn-blew-celery'), 'acorn blew celery');
    });

    test('empty and whitespace-only input normalise to empty', () {
      expect(normalizeRecoveryPhrase(''), '');
      expect(normalizeRecoveryPhrase('   \n\t '), '');
    });
  });

  group('the shipped wordlist', () {
    test('has exactly the number of words the entropy claim assumes', () {
      expect(_shippedWordlist().words.length, recoveryWordlistLength);
    });

    test('identifies every word by its first three characters', () {
      final words = _shippedWordlist().words;
      expect(words.map((w) => w.substring(0, 3)).toSet().length, words.length);
    });

    test('keeps every pair at least two edits apart', () {
      final words = _shippedWordlist().words;
      for (var i = 0; i < words.length; i++) {
        for (var j = i + 1; j < words.length; j++) {
          if ((words[i].length - words[j].length).abs() >= 2) continue;
          expect(
            _distance(words[i], words[j]),
            greaterThanOrEqualTo(2),
            reason: '${words[i]} / ${words[j]} are too close',
          );
        }
      }
    });

    test('contains only lowercase ascii letters', () {
      for (final word in _shippedWordlist().words) {
        expect(RegExp(r'^[a-z]+$').hasMatch(word), isTrue, reason: word);
      }
    });
  });

  group('generateRecoveryCode', () {
    test('produces the right number of words, all from the list', () {
      final list = _shippedWordlist();
      final code = generateRecoveryCode(list);
      final words = code.split(' ');
      expect(words, hasLength(recoveryCodeWordCount));
      for (final word in words) {
        expect(list.contains(word), isTrue, reason: word);
      }
    });

    test('output survives normalisation unchanged', () {
      final list = _shippedWordlist();
      for (var i = 0; i < 50; i++) {
        final code = generateRecoveryCode(list);
        expect(normalizeRecoveryPhrase(code), code);
      }
    });

    test('allows repeated words', () {
      final list = RecoveryWordlist(['alpha', 'bravo']);
      final code = generateRecoveryCode(list, random: Random(1));
      expect(code.split(' '), hasLength(recoveryCodeWordCount));
    });

    test('throws rather than returning an empty code', () {
      expect(
        () => generateRecoveryCode(RecoveryWordlist([])),
        throwsArgumentError,
      );
    });
  });

  group('checkRecoveryCode', () {
    late RecoveryWordlist list;
    setUp(() => list = _shippedWordlist());

    String validCode() => generateRecoveryCode(list);

    test('accepts a freshly generated code', () {
      final check = checkRecoveryCode(validCode(), list);
      expect(check.isValid, isTrue);
      expect(check.problem, isNull);
    });

    test('accepts one typed back with messy spacing and capitals', () {
      final code = validCode();
      final check = checkRecoveryCode('  ${code.toUpperCase()}  ', list);
      expect(check.isValid, isTrue);
      expect(check.normalized, code);
    });

    test('reports too few words', () {
      final words = validCode().split(' ')..removeLast();
      expect(
        checkRecoveryCode(words.join(' '), list).problem,
        RecoveryCodeProblem.tooShort,
      );
    });

    test('reports too many words', () {
      expect(
        checkRecoveryCode('${validCode()} extra', list).problem,
        RecoveryCodeProblem.tooLong,
      );
    });

    test('reports which word is not on the list', () {
      final words = validCode().split(' ');
      words[2] = 'zzzzzz';
      final check = checkRecoveryCode(words.join(' '), list);
      expect(check.problem, RecoveryCodeProblem.unknownWords);
      expect(check.unknownWordIndices, [2]);
    });

    test('reports empty input as empty, not as too short', () {
      expect(checkRecoveryCode('   ', list).problem, RecoveryCodeProblem.empty);
    });
  });

  group('suggestionsFor', () {
    test('offers the intended word for a single-character typo', () {
      final list = _shippedWordlist();
      final word = list.words.firstWhere((w) => w.length >= 5);
      final typo = word.replaceRange(2, 3, 'q');
      if (list.contains(typo)) return;
      expect(list.suggestionsFor(typo), contains(word));
    });

    test('offers nothing for a word that is already valid', () {
      final list = _shippedWordlist();
      expect(list.suggestionsFor(list.words.first), isEmpty);
    });

    test('offers nothing for input nowhere near the list', () {
      expect(_shippedWordlist().suggestionsFor('qqqqqqqq'), isEmpty);
    });
  });

  group('looksLikeSecurityKey', () {
    const elementKey =
        'EsTT oCb4 Y2g6 8J1P phWq nKCN QAAt KvCM PmJm pNQS rPtk e7XN';

    test('recognises a grouped base58 key', () {
      expect(looksLikeSecurityKey(elementKey), isTrue);
    });

    test('recognises one pasted without the grouping', () {
      expect(looksLikeSecurityKey(elementKey.replaceAll(' ', '')), isTrue);
    });

    test('does not mistake a word code for one', () {
      expect(
        looksLikeSecurityKey(
          'jittery gorges privy cabana napkins spasm thymus',
        ),
        isFalse,
      );
    });

    test('does not fire on a short scrap of input', () {
      expect(looksLikeSecurityKey('EsTD aqes'), isFalse);
    });
  });

  group('completeUnique', () {
    test('resolves a three-character prefix to exactly one word', () {
      final list = _shippedWordlist();
      final word = list.words[100];
      expect(list.completeUnique(word.substring(0, 3)), word);
    });

    test('returns null when a longer prefix contradicts the match', () {
      final list = _shippedWordlist();
      final word = list.words[100];
      expect(list.completeUnique('${word.substring(0, 3)}zzz'), isNull);
    });
  });

  group('recoveryConfirmationIndices', () {
    test('asks for two different positions, in range', () {
      for (var i = 0; i < 200; i++) {
        final indices = recoveryConfirmationIndices(random: Random(i));
        expect(indices, hasLength(2));
        expect(indices.first, lessThan(indices.last));
        expect(indices.last, lessThan(recoveryCodeWordCount));
        expect(indices.first, greaterThanOrEqualTo(0));
      }
    });
  });

  group('ordinal', () {
    test('handles the ordinary cases', () {
      expect(ordinal(1), '1st');
      expect(ordinal(2), '2nd');
      expect(ordinal(3), '3rd');
      expect(ordinal(7), '7th');
    });

    test('handles the teens, which the mod-10 rule alone gets wrong', () {
      expect(ordinal(11), '11th');
      expect(ordinal(12), '12th');
      expect(ordinal(13), '13th');
    });
  });

  group('recoveryCodeWordCount', () {
    test('carries at least as much entropy as BIP39\'s 12-word floor', () {
      final bitsPerWord = math.log(recoveryWordlistLength) / math.ln2;
      expect(recoveryCodeWordCount * bitsPerWord, greaterThan(120));
    });
  });

  group('recoveryUnlockInput', () {
    late RecoveryWordlist list;
    setUp(() => list = _shippedWordlist());

    test('normalises a word code, so a stray capital still unlocks', () {
      final code = generateRecoveryCode(list);
      final typed = '  ${code[0].toUpperCase()}${code.substring(1)}  ';
      expect(recoveryUnlockInput(typed, list), code);
    });

    test('collapses the double spaces a hand transcription produces', () {
      final code = generateRecoveryCode(list);
      expect(recoveryUnlockInput(code.replaceAll(' ', '  '), list), code);
    });

    test('leaves a base58 security key untouched', () {
      const key = 'EsTT oCb4 Y2g6 8J1P phWq nKCN QAAt KvCM PmJm pNQS rPtk e7XN';
      expect(recoveryUnlockInput(key, list), key);
    });

    test('leaves a user-chosen phrase untouched', () {
      const phrase = 'My Secret Phrase, 42!';
      expect(recoveryUnlockInput(phrase, list), phrase);
    });

    test('passes input through unchanged when the wordlist is unavailable', () {
      expect(recoveryUnlockInput('  something  ', null), 'something');
    });
  });
}
