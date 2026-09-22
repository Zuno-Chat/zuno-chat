import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/notify_me.dart';

void main() {
  Future<NotifyMe> read(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    return notifyMeFromPreferences(await SharedPreferences.getInstance());
  }

  test('reads a stored mentions-only setting', () async {
    expect(
      await read({notifyMePreferenceKey: 'mentionsOnly'}),
      NotifyMe.mentionsOnly,
    );
  });

  test('reads a stored all-messages setting', () async {
    expect(await read({notifyMePreferenceKey: 'all'}), NotifyMe.all);
  });

  test('notifies for everything when nothing has been stored', () async {
    expect(await read({}), NotifyMe.all);
  });

  test('notifies for everything when the stored value is unrecognized',
      () async {
    expect(await read({notifyMePreferenceKey: 'onlyOnTuesdays'}), NotifyMe.all);
  });

  test('notifies for everything for an empty stored value', () async {
    expect(await read({notifyMePreferenceKey: ''}), NotifyMe.all);
  });

  test('reads the same key the settings screen writes', () {
    expect(notifyMePreferenceKey, 'settings.notify_me');
  });
}
