import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../errors/caught_errors.dart';

const _notifiedEventsKey = 'notifications.notified_events';
const maxNotifiedEvents = 256;

Future<void> markEventNotifiedOnDisk(
  SharedPreferences prefs,
  String eventId,
) async {
  final ids = [...readNotifiedEventIds(prefs)]
    ..remove(eventId)
    ..add(eventId);
  if (ids.length > maxNotifiedEvents) {
    ids.removeRange(0, ids.length - maxNotifiedEvents);
  }
  await prefs.setStringList(_notifiedEventsKey, ids);
}

List<String> readNotifiedEventIds(SharedPreferences prefs) {
  try {
    return prefs.getStringList(_notifiedEventsKey) ?? const [];
  } catch (e, s) {
    reportCaught('notified events read', e, s);
    return const [];
  }
}

bool wasEventNotified(SharedPreferences prefs, String eventId) =>
    readNotifiedEventIds(prefs).contains(eventId);

Future<void> _forgetNotifiedOnDisk(SharedPreferences prefs, String id) async {
  final ids = readNotifiedEventIds(prefs);
  if (!ids.contains(id)) return;
  await prefs.setStringList(_notifiedEventsKey, [...ids]..remove(id));
}

const _placeholderPrefix = 'placeholder:';

Future<void> markPlaceholderShownOnDisk(
  SharedPreferences prefs,
  String eventId,
) => markEventNotifiedOnDisk(prefs, '$_placeholderPrefix$eventId');

bool wasPlaceholderShown(SharedPreferences prefs, String eventId) =>
    wasEventNotified(prefs, '$_placeholderPrefix$eventId');

Future<void> forgetPlaceholderShownOnDisk(
  SharedPreferences prefs,
  String eventId,
) => _forgetNotifiedOnDisk(prefs, '$_placeholderPrefix$eventId');

const _announcedInvitesKey = 'notifications.announced_invites';
const inviteAnnouncementMemory = Duration(days: 7);

Map<String, int> _announcedInvites(SharedPreferences prefs, DateTime now) {
  final Object? decoded;
  try {
    decoded = jsonDecode(prefs.getString(_announcedInvitesKey) ?? '{}');
  } on FormatException {
    return {};
  } catch (e, s) {
    reportCaught('announced invites read', e, s);
    return {};
  }
  if (decoded is! Map) return {};
  final cutoff = now.subtract(inviteAnnouncementMemory).millisecondsSinceEpoch;
  return {
    for (final MapEntry(:key, :value) in decoded.entries)
      if (key is String && value is int && value > cutoff) key: value,
  };
}

DateTime? inviteAnnouncedAt(SharedPreferences prefs, String roomId) {
  final at = _announcedInvites(prefs, clock.now())[roomId];
  return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
}

Future<void> markInviteAnnouncedOnDisk(
  SharedPreferences prefs,
  String roomId, {
  required DateTime now,
}) {
  final announced = _announcedInvites(prefs, now)
    ..[roomId] = now.millisecondsSinceEpoch;
  return prefs.setString(_announcedInvitesKey, jsonEncode(announced));
}

Future<bool> forgetInviteAnnouncementsOnDisk(
  SharedPreferences prefs,
  Iterable<String> roomIds,
) async {
  final announced = _announcedInvites(prefs, clock.now());
  final before = announced.length;
  final settled = roomIds.toSet();
  announced.removeWhere((roomId, _) => settled.contains(roomId));
  if (announced.length == before) return false;
  await prefs.setString(_announcedInvitesKey, jsonEncode(announced));
  return true;
}
