import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/notify_me.dart';

void main() {
  Future<NotifyMe> read(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    return notifyMeFromPreferences(await SharedPreferences.getInstance());
  }

  for (final (name, stored, expected) in [
    (
      'reads a stored mentions-only setting',
      {notifyMePreferenceKey: 'mentionsOnly'},
      NotifyMe.mentionsOnly,
    ),
    (
      'reads a stored all-messages setting',
      {notifyMePreferenceKey: 'all'},
      NotifyMe.all,
    ),
    (
      'notifies for everything when nothing has been stored',
      <String, Object>{},
      NotifyMe.all,
    ),
    (
      'notifies for everything when the stored value is unrecognized',
      {notifyMePreferenceKey: 'onlyOnTuesdays'},
      NotifyMe.all,
    ),
  ]) {
    test(name, () async {
      expect(await read(stored), expected);
    });
  }
}
