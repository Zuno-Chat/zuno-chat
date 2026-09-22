import 'package:shared_preferences/shared_preferences.dart';

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
  } catch (_) {
    return const [];
  }
}

bool wasEventNotified(SharedPreferences prefs, String eventId) =>
    readNotifiedEventIds(prefs).contains(eventId);

const _placeholderPrefix = 'placeholder:';

Future<void> markPlaceholderShownOnDisk(
  SharedPreferences prefs,
  String eventId,
) => markEventNotifiedOnDisk(prefs, '$_placeholderPrefix$eventId');

bool wasPlaceholderShown(SharedPreferences prefs, String eventId) =>
    wasEventNotified(prefs, '$_placeholderPrefix$eventId');
