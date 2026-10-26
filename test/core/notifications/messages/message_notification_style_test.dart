import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/messages/message_notification_content.dart';
import 'package:zuno/core/notifications/messages/message_notifications.dart';
import 'package:zuno/core/notifications/messages/notification_avatar_cache.dart';
import 'package:zuno/core/notifications/messages/notification_ids.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/messages/notified_events_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/test_clock.dart';

void main() {
  const roomId = '!room:example.org';
  final roomNotificationId = messageNotificationIdFor(roomId);
  final noon = DateTime.utc(2031, 1, 1, 12);
  late RecordedNotifications notifications;
  late RecordedMethodCalls conversations;
  late Directory avatarDir;
  var preview = NotificationPreview.full;
  final clockedTest = testsOnClock(() => DateTime(2031, 6));

  setUp(() async {
    preview = NotificationPreview.full;
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

  tearDown(() => NotificationAvatarCache.instance = NotificationAvatarCache());

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
    bool quiet = false,
  }) => MessageNotifications.instance.showMessage(
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
      quiet: quiet,
    ),
    preview: preview,
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

  clockedTest(
    'posts a MessagingStyle line with the sender as the person',
    () async {
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
    },
  );

  clockedTest('a direct chat has no conversation title', () async {
    await post(eventId: r'$1');

    final style = (lastRoomPost()['styleInformation'] as Map);
    expect(style['conversationTitle'], isNull);
    expect(style['groupConversation'], isFalse);
  });

  clockedTest('a group chat is titled and flagged as a group', () async {
    await post(eventId: r'$1', title: 'Team', isGroupChat: true);

    final style = (lastRoomPost()['styleInformation'] as Map);
    expect(style['conversationTitle'], 'Team');
    expect(style['groupConversation'], isTrue);
  });

  clockedTest(
    'accumulates lines while the notification is still showing',
    () async {
      await post(eventId: r'$1', text: 'hi');
      showing();
      await post(eventId: r'$2', text: 'there?');

      expect(messagesOf(lastRoomPost()).map((m) => m['text']), [
        'hi',
        'there?',
      ]);
    },
  );

  clockedTest('a chat still on screen keeps its lines however many other chats '
      'came and went since', () async {
    await post(eventId: r'$1', text: 'hi');
    showing();
    for (var i = 0; i < maxNotificationThreads; i++) {
      await post(room: '!other$i:x', eventId: '\$o$i', text: 'other');
    }

    await post(eventId: r'$2', text: 'there?');

    expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['hi', 'there?']);
  });

  clockedTest('a post under a thread of its own keeps apart from the room\'s '
      'notification, its lines and its instant notice', () async {
    const own = 'knock:$roomId:@ines:x';
    await post(eventId: r'$1', text: 'hi');
    showing();
    final noticed = installFakeConversationsChannel(noticed: {roomId: r'$m'});
    final forget = MessageNotifications.instance.expectPushNotice(
      roomId,
      r'$m',
    );
    addTearDown(forget);

    await MessageNotifications.instance.showMessage(
      MessageNotificationContent(
        roomId: roomId,
        threadKey: own,
        title: 'Beginners',
        body: 'Ines asks to join',
        text: 'Ines asks to join',
        eventId: r'$knock',
        isDirectChat: false,
        senderId: '@ines:x',
        senderName: 'Ines',
        timestamp: noon,
      ),
      preview: preview,
    );

    final knock = notifications.shown.last;
    expect(knock.id, messageNotificationIdFor(own));
    expect(jsonDecode(knock.payload)['roomId'], roomId);
    expect(messagesOf(knock.android).map((m) => m['text']), [
      'Ines asks to join',
    ]);
    expect(noticed.takenNotices, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(readNotificationThread(prefs, roomId)?.lines, hasLength(1));
    expect(readNotificationThread(prefs, own)?.roomId, roomId);
  });

  clockedTest(
    'starts afresh once the user has swiped the old thread away',
    () async {
      await post(eventId: r'$1', text: 'hi');
      await post(eventId: r'$2', text: 'there?');

      expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['there?']);
    },
  );

  clockedTest(
    'posts no group summary of its own, since an action can cancel the '
    'last chat natively and leave a summary stranded',
    () async {
      await post(eventId: r'$1');

      expect(notifications.summaries, isEmpty);
      expect(lastRoomPost()['groupKey'], isNull);
    },
  );

  clockedTest(
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

  clockedTest('a placeholder pushes no conversation shortcut, the message that '
      'replaces it does', () async {
    await post(eventId: r'$1', text: 'New message', placeholder: true);
    expect(conversations.named('pushConversationShortcut'), isEmpty);
    showing();

    await post(eventId: r'$1', text: 'hello');

    expect(conversations.named('pushConversationShortcut'), hasLength(1));
  });

  clockedTest('a refinement pushes no conversation shortcut again', () async {
    await post(eventId: r'$1');
    showing();

    await post(eventId: r'$1', refine: true, senderAvatar: Uint8List(1));

    expect(conversations.named('pushConversationShortcut'), hasLength(1));
  });

  clockedTest(
    'taking a placeholder back pushes no conversation shortcut',
    () async {
      await post(eventId: r'$1');
      showing();
      await post(eventId: r'$2', text: 'New message', placeholder: true);

      await MessageNotifications.instance.retractPlaceholder(
        roomId,
        r'$2',
        preview: preview,
      );

      expect(conversations.named('pushConversationShortcut'), hasLength(1));
    },
  );

  clockedTest('carries the unread count as the badge number', () async {
    await post(eventId: r'$1', unreadCount: 5);

    expect(lastRoomPost()['number'], 5);
  });

  clockedTest('a placeholder is replaced in place by the real message, without '
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

  clockedTest(
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

  clockedTest(
    'a refinement leaves the notified list alone, since its first post '
    'already wrote it',
    () async {
      await post(eventId: r'$1');
      showing();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notifications.notified_events');

      await post(eventId: r'$1', refine: true, senderAvatar: Uint8List(1));

      await prefs.reload();
      expect(readNotifiedEventIds(prefs), isEmpty);
      expect(notifications.shown, hasLength(2));
    },
  );

  clockedTest(
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

  clockedTest(
    'a message right after an instant notice in the same room does not '
    'chime a second time',
    () async {
      installFakeConversationsChannel(noticed: {roomId: r'$1'});
      showing();

      await post(eventId: r'$1');
      await post(eventId: r'$2', text: 'and another');

      expect(lastRoomPost()['onlyAlertOnce'], isTrue);
    },
  );

  group('quiet messages', () {
    clockedTest('go to the quiet channel without alerting', () async {
      await post(eventId: r'$1', quiet: true);

      expect(lastRoomPost()['channelId'], 'quiet_messages');
      expect(lastRoomPost()['silent'], isTrue);
    });

    clockedTest(
      'a mention after quiet lines alerts on the chat channel',
      () async {
        await post(eventId: r'$1', quiet: true);
        showing();

        await post(eventId: r'$2', text: 'hey @me');

        expect(lastRoomPost()['channelId'], 'direct_messages');
        expect(lastRoomPost()['silent'], isFalse);
        expect(lastRoomPost()['onlyAlertOnce'], isFalse);
        expect(messagesOf(lastRoomPost()), hasLength(2));
      },
    );

    clockedTest('a quiet line joining a mention stays on the chat channel, '
        'silently', () async {
      await post(eventId: r'$1', text: 'hey @me');
      showing();

      await post(eventId: r'$2', quiet: true);

      expect(lastRoomPost()['channelId'], 'direct_messages');
      expect(lastRoomPost()['onlyAlertOnce'], isTrue);
    });

    clockedTest(
      'a quiet placeholder that turns out to be a mention alerts',
      () async {
        await post(
          eventId: r'$1',
          text: 'New message',
          placeholder: true,
          quiet: true,
        );
        showing();

        await post(eventId: r'$1', text: 'hey @me');

        expect(lastRoomPost()['channelId'], 'direct_messages');
        expect(lastRoomPost()['onlyAlertOnce'], isFalse);
        expect(lastRoomPost()['silent'], isFalse);
      },
    );
  });

  clockedTest('cancelling forgets the thread', () async {
    await post(eventId: r'$1');

    await MessageNotifications.instance.cancelMessageNotification(roomId);

    final prefs = await SharedPreferences.getInstance();
    expect(readNotificationThread(prefs, roomId), isNull);
    expect(notifications.cancelled, [roomNotificationId]);
  });

  clockedTest(
    'retracting a lone placeholder takes the notification down',
    () async {
      await post(eventId: r'$1', text: 'New message', placeholder: true);
      showing();

      await MessageNotifications.instance.retractPlaceholder(
        roomId,
        r'$1',
        preview: preview,
      );

      expect(notifications.cancelled, contains(roomNotificationId));
      final prefs = await SharedPreferences.getInstance();
      expect(readNotificationThread(prefs, roomId), isNull);
    },
  );

  clockedTest(
    'retracting a placeholder re-posts the other lines silently',
    () async {
      await post(eventId: r'$1', text: 'hi');
      showing();
      await post(eventId: r'$2', text: 'New message', placeholder: true);

      await MessageNotifications.instance.retractPlaceholder(
        roomId,
        r'$2',
        preview: preview,
      );

      expect(messagesOf(lastRoomPost()).map((m) => m['text']), ['hi']);
      expect(lastRoomPost()['onlyAlertOnce'], isTrue);
      expect(notifications.cancelled, isNot(contains(roomNotificationId)));
    },
  );

  clockedTest(
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

  clockedTest(
    'a repeat placeholder for the same event does not add a second line',
    () async {
      await post(eventId: r'$1', text: 'New message', placeholder: true);
      showing();

      await post(eventId: r'$1', text: 'New message', placeholder: true);

      expect(messagesOf(lastRoomPost()), hasLength(1));
    },
  );

  clockedTest('a refinement can attach an image to its line', () async {
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

  clockedTest(
    'an attached image survives the next line being appended',
    () async {
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
    },
  );

  clockedTest(
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

  group('posts racing in one room', () {
    List<String?> linesOfLastPost() =>
        messagesOf(lastRoomPost()).map((m) => m['text'] as String?).toList();

    void noticePendingFor(String eventId) =>
        installFakeConversationsChannel(noticed: {roomId: eventId});

    clockedTest('two posts at once both keep their line', () async {
      showing();

      await Future.wait([
        post(eventId: r'$1', text: 'one'),
        post(
          eventId: r'$2',
          text: 'two',
          timestamp: noon.add(const Duration(seconds: 1)),
        ),
      ]);

      expect(linesOfLastPost(), ['one', 'two']);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(readNotificationThread(prefs, roomId)!.lines.map((l) => l.text), [
        'one',
        'two',
      ]);
      expect(wasEventNotified(prefs, r'$1'), isTrue);
      expect(wasEventNotified(prefs, r'$2'), isTrue);
    });

    clockedTest(
      'an older message posted after a newer one reads in time order, and '
      'the notification leads with the newest',
      () async {
        final later = noon.add(const Duration(minutes: 1));
        await post(eventId: r'$2', text: 'newer', timestamp: later);
        showing();

        await post(eventId: r'$1', text: 'older');

        expect(linesOfLastPost(), ['older', 'newer']);
        expect(lastRoomPost()['when'], later.millisecondsSinceEpoch);
        final shown = notifications.shown.last;
        expect(shown.body, 'newer');
        expect(jsonDecode(shown.payload)['eventId'], r'$2');
      },
    );

    clockedTest(
      'a real message replacing its placeholder moves to its own place '
      'in time',
      () async {
        await post(
          eventId: r'$late',
          text: 'New message',
          placeholder: true,
          timestamp: noon.add(const Duration(minutes: 5)),
        );
        showing();
        await post(
          eventId: r'$2',
          text: 'two',
          timestamp: noon.add(const Duration(minutes: 2)),
        );

        await post(eventId: r'$late', text: 'one');

        expect(linesOfLastPost(), ['one', 'two']);
      },
    );

    clockedTest(
      'a post that lands first takes over the instant notice another push '
      'put up, so stale lines never come back and the notice\'s own post '
      'wipes nothing',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await writeNotificationThread(
          prefs,
          NotificationThread(
            roomId: roomId,
            title: 'Alice',
            isGroupChat: false,
            lines: [
              NotificationLine(
                eventId: r'$stale',
                senderId: '@a:x',
                senderName: 'Alice',
                text: 'from yesterday',
                timestamp: noon.subtract(const Duration(days: 1)),
              ),
            ],
          ),
        );
        noticePendingFor(r'$a');
        showing();
        final forget = MessageNotifications.instance.expectPushNotice(
          roomId,
          r'$a',
        );
        addTearDown(forget);

        await post(
          eventId: r'$b',
          text: 'second',
          timestamp: noon.add(const Duration(seconds: 1)),
        );
        expect(linesOfLastPost(), ['second']);
        expect(lastRoomPost()['onlyAlertOnce'], isTrue);

        await post(eventId: r'$a', text: 'first');

        expect(linesOfLastPost(), ['first', 'second']);
      },
    );

    clockedTest(
      'a notice no push is waiting on any more is not taken',
      () async {
        noticePendingFor(r'$a');
        showing();
        MessageNotifications.instance.expectPushNotice(roomId, r'$a')();

        await post(eventId: r'$b', text: 'second');

        expect(lastRoomPost()['onlyAlertOnce'], isFalse);
      },
    );
  });

  group('at the preview level', () {
    final avatar = Uint8List.fromList([5, 5]);

    void choose(NotificationPreview level) => preview = level;

    Future<void> postWithActions({
      String eventId = r'$1',
      String text = 'New message',
      bool isGroupChat = true,
    }) => MessageNotifications.instance.showMessage(
      MessageNotificationContent(
        roomId: roomId,
        title: 'Team',
        body: 'Alice: $text',
        text: text,
        eventId: eventId,
        isDirectChat: !isGroupChat,
        senderId: '@a:x',
        senderName: 'Alice',
        senderAvatarUrl: Uri.parse('mxc://x/alice'),
        timestamp: noon,
      ),
      preview: preview,
      isMessage: true,
      senderAvatar: avatar,
    );

    clockedTest('Name and message offers Reply and Mark as read', () async {
      choose(NotificationPreview.full);

      await postWithActions(text: 'hi');

      final actions = (lastRoomPost()['actions'] as List).cast<Map>();
      expect(actions.map((a) => a['id']), ['mark_read', 'reply']);
    });

    clockedTest(
      'Name only keeps names and pictures of people, with no actions and '
      'no photos',
      () async {
        choose(NotificationPreview.nameOnly);
        await postWithActions(isGroupChat: false);
        showing();

        await post(
          eventId: r'$1',
          title: 'Team',
          text: 'New message',
          refine: true,
          imageUri: 'content://zuno/1',
          imageMimeType: 'image/jpeg',
        );

        final android = lastRoomPost();
        expect(notifications.shown.last.title, 'Team');
        expect(android['actions'], isNull);
        expect(android['largeIcon'], avatar);
        expect(android['shortcutId'], roomId);
        final line = messagesOf(android).single;
        expect(line['text'], 'New message');
        expect((line['person'] as Map)['name'], 'Alice');
        expect(line['dataUri'], isNull);
        expect(conversations.named('pushConversationShortcut'), hasLength(1));
      },
    );

    clockedTest(
      'Nothing posts "Zuno" and "New message" with no names, pictures, '
      'actions or conversation',
      () async {
        choose(NotificationPreview.nothing);

        await postWithActions(isGroupChat: false, text: 'secret plans');

        final shown = notifications.shown.last;
        expect(shown.title, 'Zuno');
        expect(shown.body, 'New message');
        expect(jsonDecode(shown.payload)['roomId'], roomId);
        final android = shown.android;
        expect(android['style'], AndroidNotificationStyle.defaultStyle.index);
        expect(
          jsonEncode(android['styleInformation']),
          isNot(contains('Alice')),
        );
        expect(android['largeIcon'], isNull);
        expect(android['shortcutId'], isNull);
        expect(android['actions'], isNull);
        expect(conversations.named('pushConversationShortcut'), isEmpty);
      },
    );

    clockedTest(
      'Nothing takes the earlier lines of a showing thread off it too',
      () async {
        await post(eventId: r'$1', text: 'from before');
        showing();
        choose(NotificationPreview.nothing);

        await post(eventId: r'$2', text: 'secret plans');

        final shown = notifications.shown.last;
        expect(shown.title, 'Zuno');
        expect(shown.body, 'New message');
        expect(
          jsonEncode(shown.android),
          allOf(isNot(contains('from before')), isNot(contains('secret'))),
        );
      },
    );

    clockedTest(
      'taking a placeholder back at Nothing re-posts the generic line',
      () async {
        choose(NotificationPreview.nothing);
        await post(eventId: r'$1', text: 'hello');
        showing();
        await post(eventId: r'$2', text: 'New message', placeholder: true);

        await MessageNotifications.instance.retractPlaceholder(
          roomId,
          r'$2',
          preview: preview,
        );

        final shown = notifications.shown.last;
        expect(notifications.shown, hasLength(3));
        expect(shown.title, 'Zuno');
        expect(shown.body, 'New message');
        expect(shown.android['shortcutId'], isNull);
        expect(shown.android['actions'], isNull);
      },
    );
  });
}
