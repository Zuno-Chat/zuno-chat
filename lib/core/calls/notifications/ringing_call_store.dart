import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'call_notification_service.dart' show RingingCallInfo, ringingCallFrom;

const ringingCallKey = 'calls.ringing_notification';
const _maxAge = Duration(seconds: 45);

RingingCallInfo? readRingingCall(SharedPreferences prefs) {
  final decoded = _readStored(prefs);
  if (decoded == null) return null;
  final postedAt = decoded['postedAt'];
  if (postedAt is! int || _ageOf(postedAt) > _maxAge) return null;
  return ringingCallFrom(decoded);
}

Duration? ringAgeFor(SharedPreferences prefs, String callId) {
  final decoded = _readStored(prefs);
  if (decoded == null) return null;
  if (decoded['callId'] != callId) return null;
  final postedAt = decoded['postedAt'];
  if (postedAt is! int) return null;
  final age = _ageOf(postedAt);
  return age >= Duration.zero ? age : null;
}

Map<String, Object?>? _readStored(SharedPreferences prefs) {
  final stored = prefs.getString(ringingCallKey);
  if (stored == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return null;
  }
  return decoded is Map<String, Object?> ? decoded : null;
}

Duration _ageOf(int postedAt) =>
    clock.now().difference(DateTime.fromMillisecondsSinceEpoch(postedAt));
