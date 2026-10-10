import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../errors/caught_errors.dart';
import '../serial_lock.dart';

const _legacyKey = 'calls.resolved';
const _keyPrefix = 'calls.resolved.';
const _retention = Duration(minutes: 5);
const _maxEntries = 32;

Future<void> markCallResolvedOnDisk(
  SharedPreferences prefs,
  String callId, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  await _moveLegacyValue(prefs, now: at);
  await prefs.setInt('$_keyPrefix$callId', at.millisecondsSinceEpoch);
  await _prune(prefs, now: at);
}

Set<String> readResolvedCallIds(SharedPreferences prefs, {DateTime? now}) {
  final cutoff = _cutoff(now ?? DateTime.now());
  return {
    for (final entry in _legacyEntries(prefs).entries)
      if (entry.value >= cutoff) entry.key,
    for (final entry in _entries(prefs).entries)
      if (entry.value >= cutoff) entry.key,
  };
}

int _cutoff(DateTime now) => now.subtract(_retention).millisecondsSinceEpoch;

Map<String, int> _entries(SharedPreferences prefs) => {
  for (final key in prefs.getKeys())
    if (key.startsWith(_keyPrefix))
      if (prefs.get(key) case final int at)
        key.substring(_keyPrefix.length): at,
};

Map<String, int> _legacyEntries(SharedPreferences prefs) {
  final stored = prefs.getString(_legacyKey);
  if (stored == null) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return {};
  }
  if (decoded is! Map<String, Object?>) return {};
  return {
    for (final entry in decoded.entries)
      if (entry.value case final int at) entry.key: at,
  };
}

Future<void> _moveLegacyValue(
  SharedPreferences prefs, {
  required DateTime now,
}) async {
  if (!prefs.containsKey(_legacyKey)) return;
  final cutoff = _cutoff(now);
  final kept = _entries(prefs);
  for (final entry in _legacyEntries(prefs).entries) {
    if (entry.value < cutoff || (kept[entry.key] ?? 0) >= entry.value) {
      continue;
    }
    await prefs.setInt('$_keyPrefix${entry.key}', entry.value);
  }
  await prefs.remove(_legacyKey);
}

Future<void> _prune(SharedPreferences prefs, {required DateTime now}) async {
  final cutoff = _cutoff(now);
  final newestFirst = _entries(prefs).entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final (index, entry) in newestFirst.indexed) {
    if (entry.value >= cutoff && index < _maxEntries) continue;
    await prefs.remove('$_keyPrefix${entry.key}');
  }
}

class ResolvedCallsMirror {
  const ResolvedCallsMirror({required this.contains, required this.add});

  final bool Function(String callId) contains;
  final void Function(String callId) add;
}

ResolvedCallsMirror? _mirror;
final _disk = SerialLock();

void attachResolvedCallsMirror(ResolvedCallsMirror mirror) => _mirror = mirror;

void detachResolvedCallsMirror(ResolvedCallsMirror mirror) {
  if (identical(_mirror, mirror)) _mirror = null;
}

Future<void> markCallResolved(String callId) {
  _mirror?.add(callId);
  return rememberCallResolved(callId);
}

Future<void> rememberCallResolved(String callId) => _disk.run(() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await markCallResolvedOnDisk(prefs, callId);
  } catch (e, s) {
    reportCaught('remember a resolved call', e, s);
  }
});

Future<bool> isCallResolved(String callId) async {
  if (_mirror?.contains(callId) ?? false) return true;
  final onDisk = await _disk.run(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return readResolvedCallIds(prefs).contains(callId);
    } catch (e, s) {
      reportCaught('read resolved calls', e, s);
      return false;
    }
  });
  if (onDisk) _mirror?.add(callId);
  return onDisk;
}
