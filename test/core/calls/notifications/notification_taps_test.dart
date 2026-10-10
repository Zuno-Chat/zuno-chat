import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = CallNotificationService.instance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordedNotifications notifications;
  late List<MethodCall> callsChannel;
  Map<String, Object?>? initializeArguments;

  setUp(() async {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    SharedPreferences.setMockInitialValues({});
    callsChannel = installFakeCallsChannel(
      reply: (call) => call.method == 'canUseFullScreenIntent' ? false : null,
    ).calls;
    await service.initialize();
    initializeArguments ??= notifications.initializeArguments;
  });

  String ringPayload() => jsonEncode({
    'roomId': '!room:example.org',
    'callId': 'call1',
    'callerId': '@bob:example.org',
    'isVideo': true,
  });

  Future<void> tap({String? actionId, required String? payload}) async {
    ByteData? reply;
    await messenger.handlePlatformMessage(
      'dexterous.com/flutter/local_notifications',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('didReceiveNotificationResponse', {
          'notificationId': 1,
          'actionId': actionId,
          'input': null,
          'payload': payload,
          'notificationResponseType': actionId == null ? 0 : 1,
        }),
      ),
      (data) => reply = data,
    );
    await pumpEventQueue();
    expect(
      () => const StandardMethodCodec().decodeEnvelope(reply!),
      returnsNormally,
      reason: 'the tap handler threw',
    );
  }

  group('tapping a notification while the app runs', () {
    test('Answer on a ring hands that call to the app', () async {
      final actions = <CallNotificationResponse>[];
      final sub = service.onAction.listen(actions.add);
      addTearDown(sub.cancel);

      await tap(actionId: 'accept', payload: ringPayload());

      final action = actions.single;
      expect(action.action, CallNotificationAction.accept);
      expect(action.call.callId, 'call1');
      expect(action.call.roomId, '!room:example.org');
      expect(action.call.isVideo, isTrue);
    });

    test('a message opens its chat', () async {
      final rooms = <String>[];
      final sub = service.onMessageTap.listen(rooms.add);
      addTearDown(sub.cancel);

      await tap(
        payload: jsonEncode({'type': 'message', 'roomId': '!chat:example.org'}),
      );

      expect(rooms, ['!chat:example.org']);
    });

    test('a new sign-in opens the device list', () async {
      var opened = 0;
      final sub = service.onNewDeviceTap.listen((_) => opened++);
      addTearDown(sub.cancel);

      await tap(payload: jsonEncode({'type': 'newDevice', 'deviceId': 'ABC'}));

      expect(opened, 1);
    });

    test('an unreadable or unknown payload does nothing', () async {
      final events = <Object?>[];
      final subs = [
        service.onAction.listen(events.add),
        service.onMessageTap.listen(events.add),
        service.onNewDeviceTap.listen(events.add),
      ];
      addTearDown(() {
        for (final sub in subs) {
          sub.cancel();
        }
      });

      await tap(payload: 'not json');
      await tap(payload: null);
      await tap(payload: jsonEncode({'type': 'mystery'}));
      await tap(payload: jsonEncode({'type': 'message'}));
      await tap(actionId: 'accept', payload: jsonEncode({'roomId': 'x'}));

      expect(events, isEmpty);
    });
  });

  group('Decline while the app is closed', () {
    NotificationResponse declineResponse(String? payload) =>
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'decline',
          payload: payload,
        );

    void Function(NotificationResponse) backgroundHandler() {
      final raw = initializeArguments!['callback_handle']! as int;
      return PluginUtilities.getCallbackFromHandle(
            CallbackHandle.fromRawHandle(raw),
          )!
          as void Function(NotificationResponse);
    }

    test('reaches the running app through the decline port', () async {
      final declined = service.onHeadlessDecline.first;

      backgroundHandler()(declineResponse(ringPayload()));

      final decline = await declined.timeout(const Duration(seconds: 5));
      expect(decline.roomId, '!room:example.org');
      expect(decline.callId, 'call1');
    });

    test('with a broken payload sends nothing', () async {
      final declines = <HeadlessCallDecline>[];
      final sub = service.onHeadlessDecline.listen(declines.add);
      addTearDown(sub.cancel);

      backgroundHandler()(declineResponse('not json'));
      backgroundHandler()(declineResponse(jsonEncode({'roomId': 1})));
      backgroundHandler()(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'accept',
          payload: ringPayload(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(declines, isEmpty);
    });
  });

  test('a new sign-in is posted on the sign-ins channel and opens the device '
      'list when tapped', () async {
    await service.showNewDevice(
      deviceId: 'ABC',
      title: 'New sign-in',
      body: 'Pixel 8a signed in',
    );

    final shown = notifications.single;
    expect(shown.title, 'New sign-in');
    expect(shown.body, 'Pixel 8a signed in');
    expect(shown.android['channelId'], 'security');
    expect(jsonDecode(shown.payload), {'type': 'newDevice', 'deviceId': 'ABC'});
  });

  group('the notification that launched the app', () {
    test('a message gives its chat', () async {
      notifications.launchDetails = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': 7,
          'notificationResponseType': 0,
          'payload': jsonEncode({'type': 'message', 'roomId': '!chat:x'}),
        },
      };

      expect(await service.takeLaunchRoomIdFromNotification(), '!chat:x');
    });

    test('a ring or no launch gives no chat', () async {
      notifications.launchDetails = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': 4002,
          'notificationResponseType': 0,
          'payload': ringPayload(),
        },
      };
      expect(await service.takeLaunchRoomIdFromNotification(), isNull);

      notifications.launchDetails = const {'notificationLaunchedApp': false};
      expect(await service.takeLaunchRoomIdFromNotification(), isNull);
    });
  });

  group('settings shortcuts', () {
    test('each opens its own system screen', () async {
      await service.openNotificationSettings();
      await service.openChannelSettings('messages_v2');
      await service.openFullScreenIntentSettings();

      expect(callsChannel.map((c) => [c.method, c.arguments]), [
        ['openNotificationSettings', null],
        [
          'openChannelSettings',
          {'channelId': 'messages_v2'},
        ],
        ['openFullScreenIntentSettings', null],
      ]);
    });

    test(
      'chat channels turned down in Android settings are reported',
      () async {
        notifications.deviceChannels = [
          deviceChannel(
            messagesChannelId,
            name: 'Chat messages',
            importance: 2,
          ),
          deviceChannel('group_messages', name: 'Room messages', importance: 4),
          deviceChannel(
            'quiet_messages',
            name: 'Quiet messages',
            importance: 2,
          ),
        ];

        expect(await service.silencedChannels(), [
          (id: messagesChannelId, name: 'Chat messages'),
        ]);
      },
    );
  });
}
