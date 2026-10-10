import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ring_notification.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';

void main() {
  late Client client;
  late Room room;
  late RecordedMethodCalls callStyle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installFakeLocalNotifications();
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

  test(
    'rings with the caller\'s display name when the room knows it',
    () async {
      addCaller('Bob Jones');

      await postRingNotification(call());

      expect(lastShowArgs()['callerName'], 'Bob Jones');
    },
  );

  test('still rings for a caller the room has never heard of, under the '
      'name in their user id', () async {
    await postRingNotification(call());

    expect(lastShowArgs()['callerName'], 'Bob');
  });

  test('rings on the group call channel for a non-direct room', () async {
    addCaller('Bob');

    await postRingNotification(call());

    expect(lastShowArgs()['channelId'], 'calls_ringing_group');
  });

  test('says whether it is a voice or a video call', () async {
    addCaller('Bob');

    await postRingNotification(call(kind: CallKind.video));
    expect(lastShowArgs()['title'], 'Incoming video call');

    callStyle.clear();
    await postRingNotification(call(callId: 'call2'));
    expect(lastShowArgs()['title'], 'Incoming voice call');
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

  test(
    'fetches and passes the caller\'s avatar bytes when network is allowed',
    () async {
      final bytes = Uint8List.fromList([9, 9, 9]);
      client = buildTestClient(
        userId: '@me:example.org',
        httpClient: MockClient(
          (request) async => http.Response.bytes(bytes, 200),
        ),
      )..accessToken = 'syt_test';
      room = buildTestRoom(client);
      addCaller('Bob', avatarUrl: 'mxc://example.org/bob-avatar');

      await postRingNotification(call(), allowNetwork: true);

      expect(lastShowArgs()['avatarBytes'], bytes);
    },
  );

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

class _ScriptedPresenter implements IncomingCallPresenter {
  _ScriptedPresenter({this.outcome = RingOutcome.shown, this.whileShowing});

  final RingOutcome outcome;
  final Future<void> Function()? whileShowing;
  final cancelled = <String?>[];

  @override
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
    Future<RingingCallInfo?>? ringingNow,
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

  @override
  Future<RingingCallInfo?> activeRing() async => null;
}
