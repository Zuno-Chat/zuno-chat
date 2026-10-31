import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/ring_notification.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/notifications/messages/message_notification_content.dart';
import 'package:zuno/core/notifications/messages/message_notifications.dart';
import 'package:zuno/core/notifications/messages/notification_ids.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

void main() {
  late Client client;
  late Room room;
  late RecordedMethodCalls callStyle;
  late RecordedNotifications notifications;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    callStyle = installFakeCallStyleChannel();
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  IncomingCall call({
    CallKind kind = CallKind.voice,
    String callId = 'call1',
  }) => IncomingCall(
    room: room,
    callId: callId,
    callerId: '@bob:example.org',
    kind: kind,
  );

  Map<String, Object?> lastShowArgs() =>
      (callStyle.lastShow.arguments as Map).cast<String, Object?>();

  void addCaller(String displayName, {String? avatarUrl}) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$bob-member',
      senderId: '@bob:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@bob:example.org',
      content: {
        'membership': 'join',
        'displayname': displayName,
        'avatar_url': ?avatarUrl,
      },
    ),
  );

  void markDirect() => client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: {
      '@bob:example.org': [room.id],
    },
  );

  void setRoomState(String type, Map<String, Object?> content) => room.setState(
    buildTestEvent(
      room,
      eventId: '\$$type',
      senderId: '@bob:example.org',
      type: type,
      stateKey: '',
      content: content,
    ),
  );

  void nameRoom(String name, {String? avatarUrl}) {
    setRoomState(EventTypes.RoomName, {'name': name});
    if (avatarUrl != null) {
      setRoomState(EventTypes.RoomAvatar, {'url': avatarUrl});
    }
  }

  test('rings a one-to-one call with the caller\'s display name when the room '
      'knows it', () async {
    markDirect();
    addCaller('Bob Jones');

    await postRingNotification(call());

    expect(lastShowArgs()['name'], 'Bob Jones');
  });

  test('still rings for a caller the room has never heard of, under the '
      'name in their user id', () async {
    markDirect();

    await postRingNotification(call());

    expect(lastShowArgs()['name'], 'Bob');
  });

  test('rings a group call under the group\'s name, never the '
      'caller\'s', () async {
    addCaller('Bob Jones');
    nameRoom('Weekend hike');

    await postRingNotification(call());

    expect(lastShowArgs()['name'], 'Weekend hike');
    expect(lastShowArgs()['text'], 'Bob Jones');
  });

  test('rings a group call from a caller the room does not know with the '
      'call kind on its second line', () async {
    nameRoom('Weekend hike');

    await postRingNotification(call());

    expect(lastShowArgs()['name'], 'Weekend hike');
    expect(lastShowArgs()['text'], 'Incoming voice call');
  });

  test('rings on the group call channel for a non-direct room', () async {
    addCaller('Bob');

    await postRingNotification(call());

    expect(lastShowArgs()['channelId'], 'calls_ringing_group');
  });

  test('says under a one-to-one caller whether it is a voice or a video '
      'call', () async {
    markDirect();
    addCaller('Bob');

    await postRingNotification(call(kind: CallKind.video));
    expect(lastShowArgs()['text'], 'Incoming video call');
    expect(lastShowArgs()['isVideo'], isTrue);

    callStyle.clear();
    await postRingNotification(call(callId: 'call2'));
    expect(lastShowArgs()['text'], 'Incoming voice call');
    expect(lastShowArgs()['isVideo'], isFalse);
  });

  test('rings a call only as long as its push allows, and a call without '
      'a limit for as long as rings go', () async {
    await postRingNotification(
      IncomingCall(
        room: room,
        callId: 'call1',
        callerId: '@bob:example.org',
        kind: CallKind.voice,
        ringFor: const Duration(seconds: 20),
      ),
    );
    expect(lastShowArgs()['ringMs'], 20000);

    await postRingNotification(call(callId: 'call2'));
    expect(lastShowArgs().containsKey('ringMs'), isFalse);
  });

  test('carries the room and call an action will need', () async {
    addCaller('Bob');

    await postRingNotification(call());

    final args = lastShowArgs();
    expect(args['roomId'], room.id);
    expect(args['callId'], 'call1');
  });

  test(
    'does not fetch an avatar on the push path (allowNetwork: false)',
    () async {
      addCaller('Bob', avatarUrl: 'mxc://example.org/bob-avatar');

      await postRingNotification(call());

      expect(lastShowArgs()['avatarBytes'], isNull);
    },
  );

  Client servingAvatars(List<String> requested, Uint8List bytes) =>
      buildTestClient(
          userId: '@me:example.org',
          database: MediaCapableFakeDatabaseApi(),
          httpClient: FakeHttpClient((request) async {
            if (request.url.path.endsWith('/versions')) {
              return http.Response(
                jsonEncode({
                  'versions': ['v1.11'],
                }),
                200,
              );
            }
            requested.add(request.url.path);
            return http.Response.bytes(bytes, 200);
          }),
        )
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'syt_test';

  test('fetches and passes the caller\'s picture for a one-to-one call when '
      'network is allowed', () async {
    final bytes = Uint8List.fromList([9, 9, 9]);
    final requested = <String>[];
    client = servingAvatars(requested, bytes);
    room = buildTestRoom(client);
    markDirect();
    addCaller('Bob', avatarUrl: 'mxc://example.org/bob-avatar');

    await postRingNotification(call(), allowNetwork: true);

    expect(lastShowArgs()['avatarBytes'], bytes);
    expect(requested, [contains('bob-avatar')]);
  });

  test('fetches the group\'s picture for a group call, never the '
      'caller\'s', () async {
    final bytes = Uint8List.fromList([7, 7, 7]);
    final requested = <String>[];
    client = servingAvatars(requested, bytes);
    room = buildTestRoom(client);
    addCaller('Bob', avatarUrl: 'mxc://example.org/bob-avatar');
    nameRoom('Weekend hike', avatarUrl: 'mxc://example.org/hike-avatar');

    await postRingNotification(call(), allowNetwork: true);

    expect(lastShowArgs()['avatarBytes'], bytes);
    expect(requested, [contains('hike-avatar')]);
  });

  group('the chat\'s "New message" lines', () {
    Future<void> newMessageFrom(String senderId, String eventId) async {
      await MessageNotifications.instance.showMessage(
        MessageNotificationContent(
          roomId: room.id,
          title: 'Climbing club',
          body: 'New message',
          text: 'New message',
          eventId: eventId,
          isDirectChat: false,
          senderId: senderId,
        ),
        preview: NotificationPreview.full,
        isMessage: true,
        placeholder: true,
      );
      notifications.active = [
        {
          'id': messageNotificationIdFor(room.id),
          'channelId': 'group_messages',
          'payload': '',
        },
      ];
    }

    Future<List<String>> linesLeft() async {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final line in readNotificationThread(prefs, room.id)?.lines ?? [])
          line.senderId,
      ];
    }

    test('from the caller are taken down once the ring shows, other '
        'people\'s stay', () async {
      await newMessageFrom('@bob:example.org', r'$1');
      await newMessageFrom('@carol:example.org', r'$2');

      await postRingNotification(call());

      expect(await linesLeft(), ['@carol:example.org']);
      expect(notifications.shown.last.lineTexts, ['New message']);
    });

    test('stay on an iPhone, where CallKit rings rather than a '
        'notification', () async {
      await newMessageFrom('@bob:example.org', r'$1');
      ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);

      await postRingNotification(call(), presenter: _ScriptedPresenter());

      expect(await linesLeft(), ['@bob:example.org']);
    });

    test('stay while the ring cannot be shown', () async {
      await newMessageFrom('@bob:example.org', r'$1');

      await postRingNotification(
        call(),
        presenter: _ScriptedPresenter(outcome: RingOutcome.unavailable),
      );

      expect(await linesLeft(), ['@bob:example.org']);
    });

    test('stay when the call ended while it was being rung', () async {
      await newMessageFrom('@bob:example.org', r'$1');

      await postRingNotification(
        call(),
        presenter: _ScriptedPresenter(
          whileShowing: () => markCallResolved('call1'),
        ),
      );

      expect(await linesLeft(), ['@bob:example.org']);
    });
  });

  group('a call that ends while it is being rung', () {
    test('has its ring taken back at once, so it never rings on', () async {
      final presenter = _ScriptedPresenter(
        whileShowing: () => markCallResolved('call1'),
      );

      final outcome = await postRingNotification(call(), presenter: presenter);

      expect(outcome, RingOutcome.filtered);
      expect(presenter.cancelled, ['call1']);
    });

    test('still live once rung, keeps its ring', () async {
      final presenter = _ScriptedPresenter();

      final outcome = await postRingNotification(call(), presenter: presenter);

      expect(outcome, RingOutcome.shown);
      expect(presenter.cancelled, isEmpty);
    });

    test('never shown, has nothing taken back', () async {
      final presenter = _ScriptedPresenter(
        outcome: RingOutcome.unavailable,
        whileShowing: () => markCallResolved('call1'),
      );

      final outcome = await postRingNotification(call(), presenter: presenter);

      expect(outcome, RingOutcome.unavailable);
      expect(presenter.cancelled, isEmpty);
    });
  });
}

class _ScriptedPresenter extends NoopIncomingCallPresenter {
  _ScriptedPresenter({this.outcome = RingOutcome.shown, this.whileShowing});

  final RingOutcome outcome;
  final Future<void> Function()? whileShowing;
  final cancelled = <String?>[];

  @override
  Future<RingOutcome> showIncoming({
    required String name,
    String? caller,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
    bool waiting = false,
    Duration? ringFor,
  }) async {
    await whileShowing?.call();
    return outcome;
  }

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async => cancelled.add(callId);
}
