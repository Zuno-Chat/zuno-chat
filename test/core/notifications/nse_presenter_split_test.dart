import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/matrix/currently_open_room_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/invite_notification_provider.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/notifications/notification_preview.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/read_model/opaque_thread_ids.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

class _NotifyingClient extends Client {
  _NotifyingClient() : super('test', database: FakeDatabaseApi());

  @override
  String? prevBatch = 's1';

  @override
  PushruleEvaluator get pushruleEvaluator => PushruleEvaluator.fromRuleset(
    PushRuleSet(
      underride: [
        PushRule(
          ruleId: '.m.rule.message',
          default$: true,
          enabled: true,
          conditions: [
            PushCondition(
              kind: 'event_match',
              key: 'type',
              pattern: 'm.room.message',
            ),
          ],
          actions: ['notify'],
        ),
      ],
    ),
  );
}

void main() {
  final withExtension = capabilitiesLike(
    iosCapabilities,
    nseNotifications: true,
    voipRing: true,
  );
  late _NotifyingClient client;
  late Room room;
  late RecordedNotifications notifications;
  late List<MethodCall> native;
  late ProviderContainer container;

  void inFront(bool front) =>
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        front ? AppLifecycleState.resumed : AppLifecycleState.paused,
      );

  setUp(() async {
    ambientCapabilities = withExtension;
    notifications = installFakeLocalNotifications(platform: TargetPlatform.iOS);
    installSilentNotificationSideChannels();
    native = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zuno/nse'), (
          call,
        ) async {
          native.add(call);
          if (call.method == 'threadKey') {
            return 'tok-${(call.arguments as Map)['room_id']}';
          }
          return null;
        });
    addTearDown(OpaqueThreadIds.instance.reset);
    addTearDown(() => inFront(true));
    client = _NotifyingClient()..setUserId('@me:x');
    room = buildTestRoom(client);
    room.setState(User('@a:x', displayName: 'Alice', room: room));
    client.rooms.add(room);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformCapabilitiesProvider.overrideWithValue(withExtension),
      ],
    );
    addTearDown(container.dispose);
    container.read(messageNotificationProvider);
    container.read(roomInviteNotificationProvider);
  });

  Future<void> deliver({String body = 'Lunch?'}) async {
    client.onTimelineEvent.add(
      buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@a:x',
        content: {'msgtype': MessageTypes.Text, 'body': body},
      ),
    );
    await pumpEventQueue();
  }

  Future<void> deliverInvite() async {
    client.onNotification.add(
      Event(
        eventId: 'invite_for_${room.id}',
        type: EventTypes.RoomMember,
        stateKey: '@me:x',
        senderId: '@a:x',
        originServerTs: DateTime.now(),
        content: {'membership': 'invite'},
        room: room,
      ),
    );
    await pumpEventQueue();
  }

  Iterable<MethodCall> sent(String method) =>
      native.where((call) => call.method == method);

  test(
    'in the background the extension presents, so Zuno posts nothing',
    () async {
      inFront(false);

      await deliver();

      expect(notifications.shown, isEmpty);
      expect(sent('writeShown'), isEmpty);
    },
  );

  test(
    'in front Zuno posts under the room token and tells the extension',
    () async {
      inFront(true);

      await deliver();

      expect(notifications.single.body, 'Alice: Lunch?');
      expect(
        notifications.lastPlatformSpecifics['threadIdentifier'],
        'tok-${room.id}',
      );
      expect(sent('writeShown').single.arguments, {
        'e': [r'$1'],
      });
    },
  );

  test('an inactive app posts like one in front, since the system hides the '
      'extension lines then', () async {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );

    await deliver();

    expect(notifications.single.body, 'Alice: Lunch?');
    expect(sent('writeShown').single.arguments, {
      'e': [r'$1'],
    });
  });

  test('Name only keeps the text off the screen', () async {
    inFront(true);
    await container
        .read(notificationPreviewProvider.notifier)
        .set(NotificationPreview.nameOnly);

    await deliver();

    expect(notifications.single.body, 'Alice: New message');
  });

  test('Nothing posts one generic line on a fixed thread', () async {
    inFront(true);
    await container
        .read(notificationPreviewProvider.notifier)
        .set(NotificationPreview.nothing);

    await deliver();

    expect(notifications.single.title, 'Zuno');
    expect(notifications.single.body, 'New message');
    expect(notifications.lastPlatformSpecifics['threadIdentifier'], 'zuno');
  });

  test('a message in the open room is handled without a post', () async {
    inFront(true);
    container.read(currentlyOpenRoomIdProvider.notifier).set(room.id);

    await deliver();

    expect(notifications.shown, isEmpty);
    expect(sent('writeShown'), hasLength(1));
  });

  test('an invitation in the background is left to the extension', () async {
    inFront(false);
    room.membership = Membership.invite;

    await deliverInvite();

    expect(notifications.shown, isEmpty);
    expect((await claimInviteAnnouncement(room.id)).won, isTrue);
  });

  test('an invitation shown in front is marked for the extension', () async {
    inFront(true);

    await deliverInvite();

    expect(notifications.shown, hasLength(1));
    expect(sent('writeShown').single.arguments, {
      'e': ['invite:${room.id}'],
    });
  });

  test(
    'an invitation arriving while inactive is shown like one in front',
    () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );

      await deliverInvite();

      expect(notifications.shown, hasLength(1));
      expect(sent('writeShown').single.arguments, {
        'e': ['invite:${room.id}'],
      });
    },
  );

  group('the message decision', () {
    MessageNotificationContent? decide(
      NotificationPreview preview,
      Map<String, Object?> content,
    ) => messageNotificationFor(
      client,
      buildTestEvent(room, eventId: r'$2', senderId: '@a:x', content: content),
      pushRuleAction: EvaluatedPushRuleAction()..notify = true,
      notifyMe: NotifyMe.all,
      currentlyOpenRoomId: null,
      preview: preview,
    ).content;

    test('Name only replaces the text but keeps a missed call', () {
      expect(
        decide(NotificationPreview.nameOnly, {
          'msgtype': MessageTypes.Text,
          'body': 'hi',
        })?.text,
        'New message',
      );
      expect(
        decide(NotificationPreview.nameOnly, {
          'msgtype': 'im.zuno.call_summary',
          'body': 'Missed Voice call',
          'call_id': 'c',
          'kind': 'voice',
          'status': 'missed',
        })?.text,
        'Missed Voice call',
      );
      expect(
        decide(NotificationPreview.full, {
          'msgtype': MessageTypes.Text,
          'body': 'hi',
        })?.text,
        'hi',
      );
    });
  });

  group('conversation shortcuts', () {
    test('are pushed only where notifications show avatars', () async {
      final conversations = installFakeConversationsChannel();
      const content = MessageNotificationContent(
        roomId: '!r:x',
        title: 'Alice',
        body: 'hi',
        eventId: r'$9',
      );

      await CallNotificationService(capabilities: withExtension)
          .showMessage(content);
      expect(conversations.named('pushConversationShortcut'), isEmpty);

      await CallNotificationService(
        capabilities: capabilitiesLike(
          iosCapabilities,
          notificationAvatars: true,
        ),
      ).showMessage(
        const MessageNotificationContent(
          roomId: '!s:x',
          title: 'Bob',
          body: 'hey',
          eventId: r'$10',
        ),
      );
      expect(conversations.named('pushConversationShortcut'), hasLength(1));
    });
  });

  test(
    'without the extension an iOS post keeps the room as its thread',
    () async {
      final service = CallNotificationService(
        capabilities: capabilitiesLike(
          iosCapabilities,
          nseNotifications: false,
        ),
        threadIds: OpaqueThreadIds(threadKey: (_) async => 'unused'),
      );

      await service.showMessage(
        const MessageNotificationContent(
          roomId: '!plain:x',
          title: 'Alice',
          body: 'hi',
          eventId: r'$11',
        ),
      );

      expect(
        notifications.lastPlatformSpecifics['threadIdentifier'],
        '!plain:x',
      );
    },
  );
}
