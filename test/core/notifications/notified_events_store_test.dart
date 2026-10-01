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

  group('announced invitations', () {
    const room = '!room:example.org';
    final noon = DateTime(2031, 3, 1, 12);

    test('an announced invitation is remembered with when it was '
        'announced', () async {
      await markInviteAnnouncedOnDisk(prefs, room, now: noon);

      expect(inviteAnnouncedAt(prefs, room, now: noon), noon);
      expect(inviteAnnouncedAt(prefs, '!other:example.org', now: noon), isNull);
    });

    test('forgetting one leaves the others', () async {
      await markInviteAnnouncedOnDisk(prefs, room, now: noon);
      await markInviteAnnouncedOnDisk(prefs, '!other:example.org', now: noon);

      expect(await forgetInviteAnnouncementsOnDisk(prefs, [room]), isTrue);

      expect(inviteAnnouncedAt(prefs, room, now: noon), isNull);
      expect(inviteAnnouncedAt(prefs, '!other:example.org', now: noon), noon);
    });

    test('forgetting rooms never announced writes nothing', () async {
      expect(await forgetInviteAnnouncementsOnDisk(prefs, [room]), isFalse);
      expect(prefs.getKeys(), isEmpty);
    });

    test('an announcement older than the invite memory is gone', () async {
      await markInviteAnnouncedOnDisk(prefs, room, now: noon);

      expect(
        inviteAnnouncedAt(prefs, room, now: noon.add(inviteAnnouncementMemory)),
        isNull,
      );
    });

    test('a corrupt stored value reads as nothing announced', () async {
      await prefs.setString('notifications.announced_invites', '[1,2]');

      expect(inviteAnnouncedAt(prefs, room, now: noon), isNull);
    });
  });
}
