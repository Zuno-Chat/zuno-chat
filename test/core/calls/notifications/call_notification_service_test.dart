import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/notifications/message_notification_content.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';

import '../../../helpers/fake_local_notifications.dart';

void main() {
  const callsChannel = MethodChannel('zuno/calls');

  Future<void> sendFromPlatform(String method, [Object? arguments]) async {
    await _messenger.handlePlatformMessage(
      callsChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      null,
    );
  }

  test('registers one sound-bearing channel per chat type, named plainly — '
      'silence is per post, not per channel. Must run first: initialize() '
      'only registers channels once per process', () async {
    final notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    SharedPreferences.setMockInitialValues({});

    await CallNotificationService.instance.showMessage(
      const MessageNotificationContent(
        roomId: '!room:example.org',
        title: 'Alice',
        body: 'hi',
      ),
    );

    final chatChannels = notifications.channels
        .where((c) => c['groupId'] == 'chats_group')
        .toList();
    expect(
      chatChannels.map((c) => c['id']),
      unorderedEquals([messagesChannelId, 'group_messages']),
    );
    for (final channel in chatChannels) {
      expect(channel['playSound'], isTrue, reason: '${channel['id']}');
      expect(channel['sound'], 'message_tone');
      expect(channel['soundSource'], 0);
      expect(channel['name'], isNot(contains('(sound)')));
    }
    expect(
      chatChannels.singleWhere((c) => c['id'] == messagesChannelId)['name'],
      'Messages',
    );
    expect(
      chatChannels.singleWhere((c) => c['id'] == 'group_messages')['name'],
      'Room messages',
    );
  });

  group('showMessage sound channel', () {
    var fakeNow = DateTime(2031);

    setUp(() {
      fakeNow = fakeNow.add(const Duration(days: 1));
      NotificationSoundPlayer.instance.now = () => fakeNow;
    });

    tearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);

    test('posts an alerting notification on the messages channel when the '
        'message tone setting is on', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['channelName'], 'Messages');
      expect(specifics['silent'], isFalse);
      expect(specifics['onlyAlertOnce'], isFalse);
    });

    test('posts a silent notification on the same channel when the message '
        'tone setting is off', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: false});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['silent'], isTrue);
    });

    test(
      'posts a group message on the group channel, not the direct one',
      () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
        final notifications = installFakeLocalNotifications();
        installSilentNotificationSideChannels();

        await CallNotificationService.instance.showMessage(
          const MessageNotificationContent(
            roomId: '!room:example.org',
            title: 'A group',
            body: 'hi',
            isDirectChat: false,
          ),
        );

        final specifics = notifications.lastPlatformSpecifics;
        expect(specifics['channelId'], 'group_messages');
        expect(specifics['channelName'], 'Room messages');
        expect(specifics['silent'], isFalse);
      },
    );

    test('a group message with the tone setting off stays on the group '
        'channel, silently', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: false});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'A group',
          body: 'hi',
          isDirectChat: false,
        ),
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], 'group_messages');
      expect(specifics['silent'], isTrue);
    });

    test('a second message in the same room within the rate limit is an '
        'only-alert-once update, not a silent one, so Android mutes it '
        'instead of cutting off the tone still playing', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
      );
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'are you there?',
        ),
      );

      expect(notifications.shown, hasLength(2));
      expect(notifications.shown.first.android['onlyAlertOnce'], isFalse);
      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['onlyAlertOnce'], isTrue);
      expect(specifics['silent'], isFalse);
    });

    test('a second message in another room within the rate limit is posted '
        'silent, which leaves the first tone alone', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
      );
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!other:example.org',
          title: 'Bob',
          body: 'hey',
        ),
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['silent'], isTrue);
      expect(specifics['onlyAlertOnce'], isFalse);
    });

    test('the same-room burst rule applies to group chats on their own '
        'channel', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!group:example.org',
          title: 'A group',
          body: 'hi',
          isDirectChat: false,
        ),
      );
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!group:example.org',
          title: 'A group',
          body: 'photo',
          isDirectChat: false,
        ),
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], 'group_messages');
      expect(specifics['onlyAlertOnce'], isTrue);
      expect(specifics['silent'], isFalse);
    });
  });

  test(
    'the buzz follows the post, so the channel tone is never behind it',
    () async {
      SharedPreferences.setMockInitialValues({
        messageToneEnabledKey: true,
        messageVibrationEnabledKey: true,
      });
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      NotificationSoundPlayer.instance.now = () => DateTime(2031, 3);
      addTearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);
      const vibration = MethodChannel('zuno/vibration');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(vibration, (call) async {
        notifications.methods.add(call.method);
        return call.method == 'hasVibrator' ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(vibration, null));

      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
      );

      expect(notifications.methods, containsAllInOrder(['show', 'vibrate']));
    },
  );

  group('showMessage dedupe', () {
    var fakeNow = DateTime(2031, 6);
    late RecordedNotifications notifications;

    setUp(() {
      fakeNow = fakeNow.add(const Duration(days: 1));
      NotificationSoundPlayer.instance.now = () => fakeNow;
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
    });

    tearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);

    Future<void> post({String roomId = '!room:example.org', String? eventId}) =>
        CallNotificationService.instance.showMessage(
          MessageNotificationContent(
            roomId: roomId,
            title: 'Alice',
            body: 'hi',
            eventId: eventId,
          ),
        );

    test('skips an event it already notified, so a sync catch-up cannot '
        're-alert what a push already showed', () async {
      await post(eventId: r'$e1');
      await post(eventId: r'$e1');

      expect(notifications.shown, hasLength(1));
    });

    test('skips an event another isolate already notified', () async {
      await markEventNotifiedOnDisk(
        await SharedPreferences.getInstance(),
        r'$pushed',
      );

      await post(eventId: r'$pushed');

      expect(notifications.shown, isEmpty);
    });

    test('a different event in the same room still posts', () async {
      await post(eventId: r'$e1');
      await post(eventId: r'$e2');

      expect(notifications.shown, hasLength(2));
    });

    test('a post without an eventId is never deduped', () async {
      await post();
      await post();

      expect(notifications.shown, hasLength(2));
    });

    test('a skipped post does not take the tone slot, so the next room '
        'still alerts', () async {
      await post(eventId: r'$e1');
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      await post(eventId: r'$e1');
      await post(roomId: '!other:example.org', eventId: r'$e2');

      expect(notifications.shown, hasLength(2));
      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['silent'], isFalse);
      expect(specifics['onlyAlertOnce'], isFalse);
    });
  });

  group('showMessage actions', () {
    late RecordedNotifications notifications;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
    });

    List<Map<String, Object?>> actionsOf(Map<String, Object?> android) =>
        (android['actions'] as List? ?? const [])
            .cast<Map>()
            .map((a) => a.cast<String, Object?>())
            .toList();

    test('attaches no actions by default — invites and the unresolved-push '
        'fallback share this method and neither is a room worth replying to '
        'sight unseen', () async {
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
          eventId: r'$1',
        ),
      );

      expect(actionsOf(notifications.lastPlatformSpecifics), isEmpty);
    });

    test('attaches Reply and Mark as read for a genuine message', () async {
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
          eventId: r'$1',
        ),
        includeMessageActions: true,
      );

      final actions = actionsOf(notifications.lastPlatformSpecifics);
      expect(actions.map((a) => a['id']), containsAll(['reply', 'mark_read']));
      final reply = actions.singleWhere((a) => a['id'] == 'reply');
      expect(reply['showsUserInterface'], isFalse);
      expect(reply['cancelNotification'], isTrue);
      expect((reply['inputs'] as List), isNotEmpty);
    });

    test('omits Mark as read (but keeps Reply) when there is no eventId '
        'to point setReadMarker at', () async {
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'New message',
          body: 'Tap to open',
        ),
        includeMessageActions: true,
      );

      final actions = actionsOf(notifications.lastPlatformSpecifics);
      expect(actions.map((a) => a['id']), ['reply']);
    });

    test('the payload carries eventId only when given', () async {
      await CallNotificationService.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
        includeMessageActions: true,
      );

      expect(notifications.shown.last.payload, isNot(contains('eventId')));
    });
  });

  group('cancelAllMessageNotifications', () {
    late RecordedNotifications notifications;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
    });

    test('takes down every chat notification but leaves the ring and the '
        'security alert alone', () async {
      notifications.active = [
        {'id': 11, 'channelId': 'direct_messages', 'payload': '{}'},
        {'id': 22, 'channelId': 'group_messages', 'payload': '{}'},
        {'id': 4002, 'channelId': 'calls_ringing', 'payload': '{}'},
        {'id': 33, 'channelId': 'security', 'payload': '{}'},
      ];

      await CallNotificationService.instance.cancelAllMessageNotifications();

      expect(notifications.cancelled, unorderedEquals([11, 22]));
    });

    test('is a no-op when nothing is showing', () async {
      notifications.active = const [];

      await CallNotificationService.instance.cancelAllMessageNotifications();

      expect(notifications.cancelled, isEmpty);
    });
  });

  test(
    'onMessageTap streams the room ID fired by onMessageTapForTest',
    () async {
      final future = CallNotificationService.instance.onMessageTap.first;
      CallNotificationService.instance.onMessageTapForTest('!room:example.org');
      expect(await future, '!room:example.org');
    },
  );

  test('onAction and onMessageTap are independent streams', () async {
    final actionFuture = CallNotificationService.instance.onAction.first;
    final tapFuture = CallNotificationService.instance.onMessageTap.first;
    CallNotificationService.instance.onActionForTest(
      const CallNotificationResponse(
        action: CallNotificationAction.accept,
        call: (
          roomId: '!room:example.org',
          callId: 'c1',
          callerId: '@alice:example.org',
          isVideo: false,
        ),
      ),
    );
    CallNotificationService.instance.onMessageTapForTest('!other:example.org');
    expect((await actionFuture).action, CallNotificationAction.accept);
    expect(await tapFuture, '!other:example.org');
  });

  test(
    'onHeadlessDecline streams the room+call fired by onHeadlessDeclineForTest',
    () async {
      final future = CallNotificationService.instance.onHeadlessDecline.first;
      CallNotificationService.instance.onHeadlessDeclineForTest(
        const HeadlessCallDecline(roomId: '!room:example.org', callId: 'c1'),
      );
      final decline = await future;
      expect(decline.roomId, '!room:example.org');
      expect(decline.callId, 'c1');
    },
  );

  group('callNotificationResponseFrom', () {
    const payload =
        '{"roomId":"!room:example.org","callId":"c1",'
        '"callerId":"@alice:example.org","isVideo":true}';

    test('parses an accept action with its call', () {
      final response = callNotificationResponseFrom(
        actionId: 'accept',
        payload: payload,
      );
      expect(response?.action, CallNotificationAction.accept);
      expect(response?.call.roomId, '!room:example.org');
      expect(response?.call.callId, 'c1');
      expect(response?.call.callerId, '@alice:example.org');
      expect(response?.call.isVideo, isTrue);
    });

    test('parses a decline action too', () {
      expect(
        callNotificationResponseFrom(
          actionId: 'decline',
          payload: payload,
        )?.action,
        CallNotificationAction.decline,
      );
    });

    test('ignores a body tap and a message notification', () {
      expect(
        callNotificationResponseFrom(actionId: null, payload: payload),
        isNull,
      );
      expect(
        callNotificationResponseFrom(
          actionId: 'accept',
          payload: '{"type":"message","roomId":"!room:example.org"}',
        ),
        isNull,
      );
    });

    test('ignores malformed or missing payloads instead of throwing', () {
      expect(
        callNotificationResponseFrom(actionId: 'accept', payload: null),
        isNull,
      );
      expect(
        callNotificationResponseFrom(actionId: 'accept', payload: 'not json'),
        isNull,
      );
      expect(
        callNotificationResponseFrom(actionId: 'accept', payload: '[1,2,3]'),
        isNull,
      );
    });

    test('treats a missing isVideo as a voice call', () {
      final response = callNotificationResponseFrom(
        actionId: 'accept',
        payload: '{"roomId":"!r:example.org","callId":"c1"}',
      );
      expect(response?.call.isVideo, isFalse);
    });
  });

  group('ongoing-call hang up', () {
    setUp(() async {
      installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      SharedPreferences.setMockInitialValues({});
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    test('emits when the notification hang up button fires', () async {
      final fired = CallNotificationService.instance.onHangUp.first;

      await sendFromPlatform('hangUpCall');

      await fired.timeout(const Duration(seconds: 1));
    });

    test('emits once per hang up, not once per listener', () async {
      var count = 0;
      final sub = CallNotificationService.instance.onHangUp.listen((_) {
        count++;
      });
      addTearDown(sub.cancel);

      await sendFromPlatform('hangUpCall');
      await pumpEventQueue();

      expect(count, 1);
    });

    test('ignores any other method on the calls channel', () async {
      var fired = false;
      final sub = CallNotificationService.instance.onHangUp.listen((_) {
        fired = true;
      });
      addTearDown(sub.cancel);

      await sendFromPlatform('somethingElse');
      await pumpEventQueue();

      expect(fired, isFalse);
    });
  });

  group('picture in picture', () {
    setUp(() async {
      installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      SharedPreferences.setMockInitialValues({});
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    test('tracks entering and leaving the system window', () async {
      final service = CallNotificationService.instance;
      expect(service.inPictureInPicture.value, isFalse);

      await sendFromPlatform('pictureInPictureChanged', true);
      expect(service.inPictureInPicture.value, isTrue);

      await sendFromPlatform('pictureInPictureChanged', false);
      expect(service.inPictureInPicture.value, isFalse);
    });

    test('sends eligibility and aspect ratio to the platform', () async {
      final calls = <MethodCall>[];
      _messenger.setMockMethodCallHandler(callsChannel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => _messenger.setMockMethodCallHandler(callsChannel, null),
      );

      await CallNotificationService.instance.setPictureInPicture(
        eligible: true,
        aspectWidth: 640,
        aspectHeight: 480,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setPictureInPicture');
      expect(calls.single.arguments, {
        'eligible': true,
        'aspectWidth': 640,
        'aspectHeight': 480,
      });
    });
  });

  group('proximity screen off', () {
    setUp(() async {
      installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      SharedPreferences.setMockInitialValues({});
      await CallNotificationService.instance.initialize(
        claimDeclinePort: false,
      );
    });

    test('sends the enabled flag to the platform', () async {
      final calls = <MethodCall>[];
      _messenger.setMockMethodCallHandler(callsChannel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => _messenger.setMockMethodCallHandler(callsChannel, null),
      );

      await CallNotificationService.instance.setProximityScreenOff(true);
      await CallNotificationService.instance.setProximityScreenOff(false);

      expect(calls, hasLength(2));
      expect(calls.map((c) => c.method), everyElement('setProximityScreenOff'));
      expect(calls.map((c) => c.arguments), [
        {'enabled': true},
        {'enabled': false},
      ]);
    });

    test('is a no-op when the platform side is missing', () async {
      _messenger.setMockMethodCallHandler(callsChannel, null);

      await expectLater(
        CallNotificationService.instance.setProximityScreenOff(true),
        completes,
      );
    });
  });
}

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
