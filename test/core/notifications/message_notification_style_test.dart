import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/notifications/message_notification_content.dart';
import 'package:zuno/core/notifications/notification_avatar_cache.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/notifications/notification_thread_store.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';

import '../../helpers/fake_local_notifications.dart';

void main() {
  const roomId = '!room:example.org';
  final roomNotificationId = messageNotificationIdFor(roomId);
  final noon = DateTime.utc(2031, 1, 1, 12);
  late RecordedNotifications notifications;
  late RecordedMethodCalls conversations;
  late Directory avatarDir;
  var fakeNow = DateTime(2031, 6);

  setUp(() async {
    fakeNow = fakeNow.add(const Duration(days: 1));
    NotificationSoundPlayer.instance.now = () => fakeNow;
    SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    conversations = installFakeConversationsChannel();
    avatarDir = await Directory.systemTemp.createTemp('avatars');
    addTearDown(() => avatarDir.delete(recursive: true));
    NotificationAvatarCache.instance = NotificationAvatarCache(
      directory: () async => avatarDir,
    );
  });

  tearDown(() {
    NotificationSoundPlayer.instance.now = DateTime.now;
    NotificationAvatarCache.instance = NotificationAvatarCache();
  });

  Future<void> post({
    String room = roomId,
    String title = 'Alice',
    String? body,
    String text = 'hi',
    String? eventId,
    String senderId = '@a:x',
    String senderName = 'Alice',
    Uri? senderAvatarUrl,
    Uint8List? senderAvatar,
    bool isGroupChat = false,
    DateTime? timestamp,
    int? unreadCount,
    bool placeholder = false,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
  }) => CallNotificationService.instance.showMessage(
    MessageNotificationContent(
      roomId: room,
      title: title,
      body: body ?? text,
      text: text,
      eventId: eventId,
      isDirectChat: !isGroupChat,
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      timestamp: timestamp ?? noon,
      unreadCount: unreadCount,
    ),
    senderAvatar: senderAvatar,
    placeholder: placeholder,
    refine: refine,
    imageUri: imageUri,
    imageMimeType: imageMimeType,
  );

  void showing() {
    notifications.active = [
      {'id': roomNotificationId, 'channelId': 'direct_messages', 'payload': ''},
    ];
  }

  Map<String, Object?> lastRoomPost() =>
      notifications.shown.lastWhere((n) => n.id == roomNotificationId).android;

  List<Map<String, Object?>> messagesOf(Map<String, Object?> android) =>
      ((android['styleInformation'] as Map)['messages'] as List)
          .cast<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();

  test('posts a MessagingStyle line with the sender as the person', () async {
    await post(eventId: r'$1');

    final android = lastRoomPost();
    expect(android['style'], AndroidNotificationStyle.messaging.index);
    final messages = messagesOf(android);
    expect(messages, hasLength(1));
    expect(messages.single['text'], 'hi');
    expect(messages.single['timestamp'], noon.millisecondsSinceEpoch);
    final person = (messages.single['person'] as Map).cast<String, Object?>();
    expect(person['name'], 'Alice');
    expect(person['key'], '@a:x');
    expect(android['when'], noon.millisecondsSinceEpoch);
    expect(android['showWhen'], isTrue);
  });

  test('a direct chat has no conversation title', () async {
    await post(eventId: r'$1');

    final style = (lastRoomPost()['styleInformation'] as Map);
    expect(style['conversationTitle'], isNull);
    expect(style['groupConversation'], isFalse);
  });

  test('a group chat is titled and flagged as a group', () async {
    await post(eventId: r'$1', title: 'Team', isGroupChat: true);

    final style = (lastRoomPost()['styleInformation'] as Map);
    expect(style['conversationTitle'], 'Team');
    expect(style['groupConversation'], isTrue);
  });

  test('accumulates lines while the notification is still showing', () async {
    await post(eventId: r'$1', text: 'hi');
    showing();
    await post(eventId: r'$2', text: 'there?');

    expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['hi', 'there?']);
  });

  test('starts afresh once the user has swiped the old thread away', () async {
    await post(eventId: r'$1', text: 'hi');
    await post(eventId: r'$2', text: 'there?');

    expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['there?']);
  });

  test('posts no group summary of its own, since an action can cancel the '
      'last chat natively and leave a summary stranded', () async {
    await post(eventId: r'$1');

    expect(notifications.summaries, isEmpty);
    expect(lastRoomPost()['groupKey'], isNull);
  });

  test(
    'binds the notification to a conversation shortcut for the room',
    () async {
      await post(eventId: r'$1');

      expect(lastRoomPost()['shortcutId'], roomId);
      final push = conversations.named('pushConversationShortcut').single;
      final args = (push.arguments as Map).cast<String, Object?>();
      expect(args['roomId'], roomId);
      expect(args['label'], 'Alice');
      expect(args['isGroup'], isFalse);
    },
  );

  test('carries the unread count as the badge number', () async {
    await post(eventId: r'$1', unreadCount: 5);

    expect(lastRoomPost()['number'], 5);
  });

  test('a placeholder is replaced in place by the real message, without '
      'alerting a second time', () async {
    await post(eventId: r'$1', text: 'New message', placeholder: true);
    final prefs = await SharedPreferences.getInstance();
    expect(wasEventNotified(prefs, r'$1'), isFalse);
    showing();

    await post(eventId: r'$1', text: 'hello');

    final posts = notifications.shown.where((n) => n.id == roomNotificationId);
    expect(posts, hasLength(2));
    expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['hello']);
    expect(lastRoomPost()['onlyAlertOnce'], isTrue);
    await prefs.reload();
    expect(wasEventNotified(prefs, r'$1'), isTrue);
  });

  test(
    'a refinement replaces the line of an already-notified event silently',
    () async {
      final bytes = Uint8List.fromList([9, 9, 9]);
      await post(eventId: r'$1');
      showing();

      await post(eventId: r'$1', refine: true, senderAvatar: bytes);

      final posts = notifications.shown.where(
        (n) => n.id == roomNotificationId,
      );
      expect(posts, hasLength(2));
      expect(messagesOf(lastRoomPost()), hasLength(1));
      expect(lastRoomPost()['onlyAlertOnce'], isTrue);
      expect(lastRoomPost()['largeIcon'], bytes);
    },
  );

  test(
    'remembers an avatar for the senders of earlier lines in a group',
    () async {
      final bytes = Uint8List.fromList([4, 2]);
      final url = Uri.parse('mxc://x/alice');
      await post(
        eventId: r'$1',
        title: 'Team',
        isGroupChat: true,
        senderAvatarUrl: url,
        senderAvatar: bytes,
      );
      showing();

      await post(
        eventId: r'$2',
        title: 'Team',
        isGroupChat: true,
        senderId: '@b:x',
        senderName: 'Bob',
        text: 'yo',
      );

      final messages = messagesOf(lastRoomPost());
      expect((messages[0]['person'] as Map)['icon'], bytes);
      expect((messages[1]['person'] as Map)['icon'], isNull);
    },
  );

  test('cancelling forgets the thread', () async {
    await post(eventId: r'$1');

    await CallNotificationService.instance.cancelMessageNotification(roomId);

    final prefs = await SharedPreferences.getInstance();
    expect(readNotificationThread(prefs, roomId), isNull);
    expect(notifications.cancelled, [roomNotificationId]);
  });

  test('retracting a lone placeholder takes the notification down', () async {
    await post(eventId: r'$1', text: 'New message', placeholder: true);
    showing();

    await CallNotificationService.instance.retractPlaceholder(roomId, r'$1');

    expect(notifications.cancelled, contains(roomNotificationId));
    final prefs = await SharedPreferences.getInstance();
    expect(readNotificationThread(prefs, roomId), isNull);
  });

  test('retracting a placeholder re-posts the other lines silently', () async {
    await post(eventId: r'$1', text: 'hi');
    showing();
    await post(eventId: r'$2', text: 'New message', placeholder: true);

    await CallNotificationService.instance.retractPlaceholder(roomId, r'$2');

    expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['hi']);
    expect(lastRoomPost()['onlyAlertOnce'], isTrue);
    expect(notifications.cancelled, isNot(contains(roomNotificationId)));
  });

  test(
    'a real post for a placeholder the user already dealt with is skipped',
    () async {
      await post(eventId: r'$1', text: 'New message', placeholder: true);

      await post(eventId: r'$1', text: 'hello');

      final posts = notifications.shown.where(
        (n) => n.id == roomNotificationId,
      );
      expect(posts, hasLength(1));
    },
  );

  test(
    'a repeat placeholder for the same event does not add a second line',
    () async {
      await post(eventId: r'$1', text: 'New message', placeholder: true);
      showing();

      await post(eventId: r'$1', text: 'New message', placeholder: true);

      expect(messagesOf(lastRoomPost()), hasLength(1));
    },
  );

  test('a refinement can attach an image to its line', () async {
    await post(eventId: r'$1', text: 'a cat');
    showing();

    await post(
      eventId: r'$1',
      text: 'a cat',
      refine: true,
      imageUri: 'content://zuno/1',
      imageMimeType: 'image/jpeg',
    );

    final line = messagesOf(lastRoomPost()).single;
    expect(line['dataUri'], 'content://zuno/1');
    expect(line['dataMimeType'], 'image/jpeg');
  });

  test('an attached image survives the next line being appended', () async {
    await post(eventId: r'$1', text: 'a cat');
    showing();
    await post(
      eventId: r'$1',
      text: 'a cat',
      refine: true,
      imageUri: 'content://zuno/1',
      imageMimeType: 'image/jpeg',
    );

    await post(eventId: r'$2', text: 'cute?');

    final lines = messagesOf(lastRoomPost());
    expect(lines[0]['dataUri'], 'content://zuno/1');
    expect(lines[1]['dataUri'], isNull);
  });

  test(
    'a refinement for a thread the user already dismissed is dropped',
    () async {
      await post(eventId: r'$1');

      await post(
        eventId: r'$1',
        refine: true,
        imageUri: 'content://zuno/1',
        imageMimeType: 'image/jpeg',
      );

      final posts = notifications.shown.where(
        (n) => n.id == roomNotificationId,
      );
      expect(posts, hasLength(1));
    },
  );
}
