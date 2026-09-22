import 'dart:math' as math;

const minPasswordLength = 12;

const recommendedPasswordLength = 15;

enum PasswordStrength { unusable, weak, fair, strong }

class PasswordAssessment {
  final PasswordStrength strength;
  final String? blocker;
  final String advice;

  const PasswordAssessment({
    required this.strength,
    required this.blocker,
    required this.advice,
  });

  bool get isUsable => blocker == null;
}

PasswordAssessment assessPassword(String password, {String? username}) {
  if (password.isEmpty) {
    return const PasswordAssessment(
      strength: PasswordStrength.unusable,
      blocker: null,
      advice: 'At least $minPasswordLength characters. Longer is stronger.',
    );
  }
  final length = password.runes.length;
  if (length < minPasswordLength) {
    final missing = minPasswordLength - length;
    return PasswordAssessment(
      strength: PasswordStrength.unusable,
      blocker: 'Use at least $minPasswordLength characters',
      advice: '$missing more character${missing == 1 ? '' : 's'} to go.',
    );
  }

  final lower = password.toLowerCase();

  if (username != null && username.isNotEmpty) {
    final name = username.toLowerCase();
    if (lower == name) {
      return const PasswordAssessment(
        strength: PasswordStrength.unusable,
        blocker: 'Your password is your username',
        advice: 'It is the first thing anyone trying to get in will try.',
      );
    }
    if (name.length >= 4 && lower.contains(name)) {
      return const PasswordAssessment(
        strength: PasswordStrength.unusable,
        blocker: 'Your password contains your username',
        advice: 'It is the first thing anyone trying to get in will try.',
      );
    }
  }
  if (commonPasswords.contains(lower)) {
    return const PasswordAssessment(
      strength: PasswordStrength.unusable,
      blocker: 'That is one of the most common passwords',
      advice: 'Pick something nobody else would guess.',
    );
  }
  final (:mask, :hasCommonWord) = _predictableParts(lower);
  final bits =
      _entropyBits(_uncovered(password, mask)) +
      _spanCount(mask) * _predictableSpanBits;
  if (_isRepeatedChunk(lower)) return _tooEasyToGuess;
  if (bits < _minGuessableBits) {
    if (!hasCommonWord) return _tooEasyToGuess;
    return const PasswordAssessment(
      strength: PasswordStrength.unusable,
      blocker: 'That is built on a common password',
      advice: 'Numbers or symbols added to one are the first thing tried.',
    );
  }

  if (bits >= 60) {
    return const PasswordAssessment(
      strength: PasswordStrength.strong,
      blocker: null,
      advice: 'Strong.',
    );
  }
  if (bits >= 40) {
    return PasswordAssessment(
      strength: PasswordStrength.fair,
      blocker: null,
      advice: length < recommendedPasswordLength
          ? 'Okay. A few more characters would make it much harder to guess.'
          : 'Okay.',
    );
  }
  return const PasswordAssessment(
    strength: PasswordStrength.weak,
    blocker: null,
    advice: 'Weak. Longer is the easiest way to fix it.',
  );
}

const _tooEasyToGuess = PasswordAssessment(
  strength: PasswordStrength.unusable,
  blocker: 'That is too easy to guess',
  advice: 'Avoid runs like 12345678 or aaaaaaaa.',
);

const _minGuessableBits = 20;

const _predictableSpanBits = 6;

const _minCommonWordLength = 5;

const _minRunLength = 3;

const _minKeyboardWalkLength = 4;

const _keyboardRows = [
  'qwertyuiop',
  'asdfghjkl',
  'zxcvbnm',
  '1234567890',
  '!@#\$%^&*()',
];

final _keyboardWalks = [
  for (final row in _keyboardRows) ...[row, row.split('').reversed.join()],
];

final _year = RegExp(r'(19|20)\d\d');

final _edgePadding = RegExp(r'^[^a-z]+|[^a-z]+$');

const _contextWords = [
  'zunochat',
  'february',
  'march',
  'april',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
];

final _commonWords = {
  ..._contextWords,
  for (final entry in commonPasswords)
    if (entry.replaceAll(_edgePadding, '') case final word
        when word.length >= _minCommonWordLength)
      word,
}.toList();

({List<bool> mask, bool hasCommonWord}) _predictableParts(String lower) {
  final mask = List.filled(lower.length, false);
  void cover(int start, int end) => mask.fillRange(start, end, true);

  var hasCommonWord = false;
  for (final word in _commonWords) {
    for (
      var at = lower.indexOf(word);
      at >= 0;
      at = lower.indexOf(word, at + 1)
    ) {
      hasCommonWord = true;
      cover(at, at + word.length);
    }
  }
  for (final match in _year.allMatches(lower)) {
    cover(match.start, match.end);
  }
  for (var start = 0; start < lower.length; start++) {
    for (final walk in _keyboardWalks) {
      final length = _walkLength(lower, start, walk);
      if (length >= _minKeyboardWalkLength) cover(start, start + length);
    }
    for (final step in const [-1, 0, 1]) {
      final length = _runLength(lower, start, step);
      if (length >= _minRunLength) cover(start, start + length);
    }
  }
  return (mask: mask, hasCommonWord: hasCommonWord);
}

int _walkLength(String lower, int start, String walk) {
  final from = walk.indexOf(lower[start]);
  if (from < 0) return 0;
  var length = 1;
  while (start + length < lower.length &&
      from + length < walk.length &&
      lower[start + length] == walk[from + length]) {
    length++;
  }
  return length;
}

int _runLength(String lower, int start, int step) {
  var length = 1;
  while (start + length < lower.length &&
      lower.codeUnitAt(start + length) - lower.codeUnitAt(start + length - 1) ==
          step) {
    length++;
  }
  return length;
}

String _uncovered(String password, List<bool> mask) {
  final kept = StringBuffer();
  for (var i = 0; i < password.length; i++) {
    if (!mask[i]) kept.write(password[i]);
  }
  return kept.toString();
}

int _spanCount(List<bool> mask) {
  var spans = 0;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] && (i == 0 || !mask[i - 1])) spans++;
  }
  return spans;
}

double _entropyBits(String password) {
  var pool = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) pool += 26;
  if (RegExp(r'[A-Z]').hasMatch(password)) pool += 26;
  if (RegExp(r'[0-9]').hasMatch(password)) pool += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) pool += 32;
  if (pool == 0) return 0;

  final distinct = password.split('').toSet().length;
  final effectiveLength = (password.length + distinct) / 2;
  return effectiveLength * (math.log(pool) / math.ln2);
}

bool _isRepeatedChunk(String value) {
  for (var unit = 1; unit <= value.length ~/ 2; unit++) {
    if (value.length % unit != 0) continue;
    final chunk = value.substring(0, unit);
    if (chunk * (value.length ~/ unit) == value) return true;
  }
  return false;
}

const commonPasswords = <String>{
  'password',
  'password1',
  'password12',
  'password123',
  'password1234',
  'passw0rd',
  'p@ssword',
  'p@ssw0rd',
  'passwords',
  'mypassword',
  'newpassword',
  'passer2009',
  'password!',
  'password@',
  '12345678',
  '123456789',
  '1234567890',
  '12345678910',
  '87654321',
  '098765432',
  '1234abcd',
  'abcd1234',
  'abc12345',
  '1234567',
  'qwertyui',
  'qwerty123',
  'qwertyuiop',
  'qwerty12',
  'qwertyu1',
  'asdfghjk',
  'asdfghjkl',
  'zxcvbnm1',
  '1qaz2wsx',
  '1q2w3e4r',
  '1q2w3e4r5t',
  'qazwsxedc',
  'zaq12wsx',
  'qweasdzxc',
  'q1w2e3r4',
  'q1w2e3r4t5y6',
  '1q2w3e4r5t6y',
  '1qaz2wsx3edc',
  'qazwsxedcrfv',
  'zaq12wsxcde3',
  'a1b2c3d4',
  'iloveyou',
  'iloveyou1',
  'iloveyou2',
  'letmein1',
  'letmein123',
  'trustno1',
  'sunshine',
  'princess',
  'football',
  'baseball',
  'basketball',
  'superman',
  'batman123',
  'starwars',
  'pokemon1',
  'michael1',
  'jennifer',
  'jordan23',
  'chocolate',
  'butterfly',
  'whatever',
  'freedom1',
  'monkey12',
  'shadow123',
  'master123',
  'dragon123',
  'hello123',
  'welcome1',
  'welcome123',
  'admin123',
  'administrator',
  'root1234',
  'toor1234',
  'default1',
  'changeme',
  'changeme1',
  'changeme123',
  'secret123',
  'temp1234',
  'test1234',
  'testing123',
  'testtest',
  'demo1234',
  'guest123',
  'computer1',
  'internet1',
  'samsung1',
  'google123',
  'facebook1',
  'twitter1',
  'matrix123',
  'element1',
  'signal123',
  'whatsapp1',
  'telegram1',
  'liverpool',
  'arsenal1',
  'chelsea1',
  'barcelona',
  'realmadrid',
  'summer2024',
  'summer2025',
  'summer2026',
  'winter2024',
  'winter2025',
  'spring2024',
  'spring2025',
  'autumn2024',
  'january1',
  'december1',
  'birthday1',
  'family123',
  'mother123',
  'daughter1',
  'sunshine1',
  'qwerty1234',
  'password01',
  'aaaaaaaa',
  'aaaaaaaaa',
  'abcdefgh',
  'abcdefghi',
  'abcdefghij',
  'zzzzzzzz',
  '00000000',
  '11111111',
  '99999999',
  'iloveu123',
  'ihateyou',
  'nopassword',
  'anonymous',
  'incorrect',
  'thisisapassword',
  'correcthorsebatterystaple',
};
