import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

const recoveryCodeWordCount = 12;

const recoveryWordlistLength = 1296;

const recoveryWordlistAsset = 'assets/wordlist/recovery_words.txt';

String normalizeRecoveryPhrase(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(RegExp(r'[a-z]').hasMatch(char) ? char : ' ');
  }
  return buffer.toString().trim().replaceAll(RegExp(r' +'), ' ');
}

List<String> recoveryCodeWords(String phrase) {
  final normalized = normalizeRecoveryPhrase(phrase);
  if (normalized.isEmpty) return const [];
  return normalized.split(' ');
}

class RecoveryWordlist {
  final List<String> words;
  final Set<String> _lookup;
  final Map<String, String> _byPrefix;

  RecoveryWordlist(List<String> words)
    : words = List.unmodifiable(words),
      _lookup = words.toSet(),
      _byPrefix = {
        for (final word in words)
          if (word.length >= 3) word.substring(0, 3): word,
      };

  static RecoveryWordlist parse(String contents) => RecoveryWordlist([
    for (final line in const LineSplitter().convert(contents))
      if (line.trim().isNotEmpty) line.trim(),
  ]);

  static Future<RecoveryWordlist> load({AssetBundle? bundle}) async {
    final contents = await (bundle ?? rootBundle).loadString(
      recoveryWordlistAsset,
    );
    return parse(contents);
  }

  bool contains(String word) => _lookup.contains(word);

  String? completeUnique(String prefix) {
    if (prefix.length < 3) {
      final matches = words.where((w) => w.startsWith(prefix)).take(2).toList();
      return matches.length == 1 ? matches.single : null;
    }
    final candidate = _byPrefix[prefix.substring(0, 3)];
    if (candidate == null || !candidate.startsWith(prefix)) return null;
    return candidate;
  }

  List<String> completions(String prefix, {int limit = 4}) {
    if (prefix.isEmpty) return const [];
    return words.where((w) => w.startsWith(prefix)).take(limit).toList();
  }

  List<String> suggestionsFor(String word, {int limit = 3}) {
    if (word.isEmpty || contains(word)) return const [];
    final near = <String>[];
    for (final candidate in words) {
      if ((candidate.length - word.length).abs() > 1) continue;
      if (_withinOneEdit(candidate, word)) {
        near.add(candidate);
        if (near.length == limit) break;
      }
    }
    return near;
  }
}

bool _withinOneEdit(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  var i = 0;
  var j = 0;
  var edited = false;
  while (i < shorter.length && j < longer.length) {
    if (shorter[i] == longer[j]) {
      i++;
      j++;
      continue;
    }
    if (edited) return false;
    edited = true;
    if (shorter.length == longer.length) {
      i++;
      j++;
    } else {
      j++;
    }
  }
  return true;
}

String generateRecoveryCode(RecoveryWordlist wordlist, {Random? random}) {
  if (wordlist.words.isEmpty) {
    throw ArgumentError('wordlist is empty');
  }
  final rng = random ?? Random.secure();
  return [
    for (var i = 0; i < recoveryCodeWordCount; i++)
      wordlist.words[rng.nextInt(wordlist.words.length)],
  ].join(' ');
}

enum RecoveryCodeProblem {
  empty,
  tooShort,
  tooLong,
  unknownWords,
}

class RecoveryCodeCheck {
  final RecoveryCodeProblem? problem;
  final List<int> unknownWordIndices;
  final String normalized;

  const RecoveryCodeCheck({
    required this.problem,
    required this.unknownWordIndices,
    required this.normalized,
  });

  bool get isValid => problem == null;
}

RecoveryCodeCheck checkRecoveryCode(String input, RecoveryWordlist wordlist) {
  final normalized = normalizeRecoveryPhrase(input);
  final words = normalized.isEmpty ? <String>[] : normalized.split(' ');
  if (words.isEmpty) {
    return RecoveryCodeCheck(
      problem: RecoveryCodeProblem.empty,
      unknownWordIndices: const [],
      normalized: normalized,
    );
  }
  final unknown = <int>[
    for (var i = 0; i < words.length; i++)
      if (!wordlist.contains(words[i])) i,
  ];
  final RecoveryCodeProblem? problem = switch (words.length) {
    < recoveryCodeWordCount => RecoveryCodeProblem.tooShort,
    > recoveryCodeWordCount => RecoveryCodeProblem.tooLong,
    _ when unknown.isNotEmpty => RecoveryCodeProblem.unknownWords,
    _ => null,
  };
  return RecoveryCodeCheck(
    problem: problem,
    unknownWordIndices: unknown,
    normalized: normalized,
  );
}

List<int> recoveryConfirmationIndices({Random? random}) {
  final rng = random ?? Random.secure();
  final first = rng.nextInt(recoveryCodeWordCount);
  var second = rng.nextInt(recoveryCodeWordCount - 1);
  if (second >= first) second++;
  return [first, second]..sort();
}

String ordinal(int oneBased) {
  if (oneBased >= 11 && oneBased <= 13) return '${oneBased}th';
  return switch (oneBased % 10) {
    1 => '${oneBased}st',
    2 => '${oneBased}nd',
    3 => '${oneBased}rd',
    _ => '${oneBased}th',
  };
}

bool looksLikeSecurityKey(String raw) {
  final compact = raw.replaceAll(RegExp(r'\s'), '');
  if (compact.length < 40) return false;
  return RegExp(r'[0-9A-Z]').hasMatch(compact);
}

String recoveryUnlockInput(String raw, RecoveryWordlist? wordlist) {
  if (wordlist == null) return raw.trim();
  final check = checkRecoveryCode(raw, wordlist);
  return check.isValid ? check.normalized : raw.trim();
}
