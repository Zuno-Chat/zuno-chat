import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'call_notification_service.dart' show RingingCallInfo;

const _ringingCallKey = 'calls.ringing_notification';
const _maxAge = Duration(seconds: 45);

Future<void> saveRingingCall(
  SharedPreferences prefs,
  RingingCallInfo call,
) async {
  await prefs.setString(
    _ringingCallKey,
    jsonEncode({
      'roomId': call.roomId,
      'callId': call.callId,
      'callerId': call.callerId,
      'isVideo': call.isVideo,
      'postedAt': DateTime.now().millisecondsSinceEpoch,
    }),
  );
}

RingingCallInfo? readRingingCall(SharedPreferences prefs, {DateTime? now}) {
  final decoded = _readStored(prefs);
  if (decoded == null) return null;
  final roomId = decoded['roomId'];
  final callId = decoded['callId'];
  final postedAt = decoded['postedAt'];
  if (roomId is! String || callId is! String || postedAt is! int) return null;
  if (_ageOf(postedAt, now) > _maxAge) return null;
  final callerId = decoded['callerId'];
  return (
    roomId: roomId,
    callId: callId,
    callerId: callerId is String ? callerId : '',
    isVideo: decoded['isVideo'] == true,
  );
}

Future<void> clearRingingCall(SharedPreferences prefs) =>
    prefs.remove(_ringingCallKey);

Duration? ringAgeFor(SharedPreferences prefs, String callId, {DateTime? now}) {
  final decoded = _readStored(prefs);
  if (decoded == null) return null;
  if (decoded['callId'] != callId) return null;
  final postedAt = decoded['postedAt'];
  if (postedAt is! int) return null;
  final age = _ageOf(postedAt, now);
  return age >= Duration.zero ? age : null;
}

Map<String, Object?>? _readStored(SharedPreferences prefs) {
  final stored = prefs.getString(_ringingCallKey);
  if (stored == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return null;
  }
  return decoded is Map<String, Object?> ? decoded : null;
}

Duration _ageOf(int postedAt, DateTime? now) => (now ?? DateTime.now())
    .difference(DateTime.fromMillisecondsSinceEpoch(postedAt));
