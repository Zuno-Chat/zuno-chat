import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a notified event is readable back', () async {
    await markEventNotifiedOnDisk(prefs, r'$one');
    await markEventNotifiedOnDisk(prefs, r'$two');

    expect(wasEventNotified(prefs, r'$one'), isTrue);
    expect(wasEventNotified(prefs, r'$two'), isTrue);
    expect(wasEventNotified(prefs, r'$three'), isFalse);
  });

  test('nothing stored reads as not notified', () {
    expect(wasEventNotified(prefs, r'$one'), isFalse);
  });

  test('only the newest entries are kept', () async {
    for (var i = 0; i < maxNotifiedEvents + 20; i++) {
      await markEventNotifiedOnDisk(prefs, '\$$i');
    }

    expect(readNotifiedEventIds(prefs), hasLength(maxNotifiedEvents));
    expect(wasEventNotified(prefs, '\$${maxNotifiedEvents + 19}'), isTrue);
    expect(wasEventNotified(prefs, r'$0'), isFalse);
  });

  test(
    'a corrupt stored value reads as not notified rather than throwing',
    () async {
      await prefs.setString('notifications.notified_events', 'not a list');

      expect(wasEventNotified(prefs, r'$one'), isFalse);
    },
  );

  test('a placeholder marker is kept apart from a real notification', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await markPlaceholderShownOnDisk(prefs, r'$p');

    expect(wasPlaceholderShown(prefs, r'$p'), isTrue);
    expect(wasEventNotified(prefs, r'$p'), isFalse);
    expect(wasPlaceholderShown(prefs, r'$other'), isFalse);
  });
}
