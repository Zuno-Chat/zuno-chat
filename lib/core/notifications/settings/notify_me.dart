import 'package:shared_preferences/shared_preferences.dart';

import '../../errors/caught_errors.dart';

enum NotifyMe { all, mentionsOnly }

const notifyMePreferenceKey = 'settings.notify_me';

NotifyMe notifyMeFromPreferences(SharedPreferences prefs) {
  final stored = prefs.getString(notifyMePreferenceKey);
  return NotifyMe.values.firstWhere(
    (mode) => mode.name == stored,
    orElse: () => NotifyMe.all,
  );
}

Future<NotifyMe> currentNotifyMe() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return notifyMeFromPreferences(prefs);
  } catch (e, s) {
    reportCaught('notify me read', e, s);
    return NotifyMe.all;
  }
}
