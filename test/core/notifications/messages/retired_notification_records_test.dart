import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/messages/notification_room_cache.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/messages/retired_notification_records.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';

import '../../../helpers/platform_capabilities.dart';

void main() {
  const retiredThreadsKey = 'notifications.threads';
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      retiredThreadsKey: '{"!r:x":{"title":"Alice","lines":[]}}',
      notificationRoomCacheKey: '!r:x\td\tAlice',
      notificationPreviewKey: 'full',
    });
    prefs = await SharedPreferences.getInstance();
  });

  test('the lines older builds kept move into the app file without their '
      'text, so a waiting line is still taken over', () async {
    SharedPreferences.setMockInitialValues({
      retiredThreadsKey:
          '{"!r:x":{"roomId":"!r:x","title":"Family","isGroupChat":true,'
          '"lines":[{"eventId":"\$1","senderId":"@a:x","senderName":"Alice",'
          '"text":"secret plans","ts":1790000000000,"placeholder":true}]}}',
    });
    prefs = await SharedPreferences.getInstance();

    await moveRetiredNotificationRecords(prefs, androidCapabilities);

    expect(prefs.getString(retiredThreadsKey), isNull);
    final moved = (await NotificationThreadStore.instance.read('!r:x'))!;
    expect(moved.isGroupChat, isTrue);
    expect(moved.lines.single.eventId, r'$1');
    expect(moved.lines.single.placeholder, isTrue);
    expect(
      jsonEncode(moved.toJson()),
      allOf(isNot(contains('secret')), isNot(contains('Alice'))),
    );
    expect(await NotificationThreadStore.instance.waitingLines(), {
      '!r:x': [(roomId: '!r:x', eventId: r'$1')],
    });
  });

  test('an iPhone drops the lines and room names older builds kept in its '
      'backed-up preferences, and nothing else', () async {
    await moveRetiredNotificationRecords(prefs, iosCapabilities);

    expect(prefs.getKeys(), {notificationPreviewKey});
  });

  test('Android drops the lines it now keeps in a file, and keeps the room '
      'directory its native push code reads', () async {
    await moveRetiredNotificationRecords(prefs, androidCapabilities);

    expect(prefs.getKeys(), {notificationRoomCacheKey, notificationPreviewKey});
  });
}
