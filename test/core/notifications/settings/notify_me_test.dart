import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:zuno/core/notifications/settings/notify_me.dart';

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

  test('the current setting sees a choice saved after this engine cached '
      'its preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    await SharedPreferencesStorePlatform.instance.setValue(
      'String',
      'flutter.$notifyMePreferenceKey',
      NotifyMe.mentionsOnly.name,
    );

    expect(await currentNotifyMe(), NotifyMe.mentionsOnly);
  });

  test('the current setting is everything when nothing was chosen', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await currentNotifyMe(), NotifyMe.all);
  });
}
