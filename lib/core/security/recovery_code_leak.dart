import 'recovery_code.dart';

const recoveryWordRunThreshold = 10;

final _securityKey = RegExp(
  r'(?:[1-9A-HJ-NP-Za-km-z]{4}[ \t]+){9,}[1-9A-HJ-NP-Za-km-z]{4}'
  r'|[1-9A-HJ-NP-Za-km-z]{40,}',
);

bool messageRevealsRecoveryCode(String text, RecoveryWordlist? wordlist) {
  if (_securityKey.hasMatch(text)) return true;
  if (wordlist == null) return false;

  var run = 0;
  for (final word in recoveryCodeWords(text)) {
    run = wordlist.contains(word) ? run + 1 : 0;
    if (run >= recoveryWordRunThreshold) return true;
  }
  return false;
}
