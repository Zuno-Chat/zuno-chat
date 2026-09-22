import 'package:shared_preferences/shared_preferences.dart';

enum NotifyMe {
  all,
  mentionsOnly,
}

const notifyMePreferenceKey = 'settings.notify_me';

NotifyMe notifyMeFromPreferences(SharedPreferences prefs) {
  final stored = prefs.getString(notifyMePreferenceKey);
  return NotifyMe.values.firstWhere(
    (mode) => mode.name == stored,
    orElse: () => NotifyMe.all,
  );
}
