import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _resolvedCallsKey = 'calls.resolved';
const _retention = Duration(minutes: 5);
const _maxEntries = 32;

Future<void> markCallResolvedOnDisk(
  SharedPreferences prefs,
  String callId, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final entries = {..._read(prefs, now: at), callId: at.millisecondsSinceEpoch};
  final ordered = entries.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  await prefs.setString(
    _resolvedCallsKey,
    jsonEncode(Map.fromEntries(ordered.take(_maxEntries))),
  );
}

Set<String> readResolvedCallIds(SharedPreferences prefs, {DateTime? now}) =>
    _read(prefs, now: now ?? DateTime.now()).keys.toSet();

Map<String, int> _read(SharedPreferences prefs, {required DateTime now}) {
  final stored = prefs.getString(_resolvedCallsKey);
  if (stored == null) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return {};
  }
  if (decoded is! Map<String, Object?>) return {};
  final cutoff = now.subtract(_retention).millisecondsSinceEpoch;
  return {
    for (final entry in decoded.entries)
      if (entry.value case final int at when at >= cutoff) entry.key: at,
  };
}
