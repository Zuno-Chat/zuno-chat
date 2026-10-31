import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/matrixrtc/ring_elsewhere_provider.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/recording_incoming_call_presenter.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';
const _thisPhone = 'THISPHONE';
const _laptop = 'LAPTOP';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;
  late Room otherRoom;
  late SharedPreferences prefs;

  setUp(() async {
    client = buildTestClient(userId: _me, deviceId: _thisPhone);
    room = buildTestRoom(client);
    otherRoom = buildTestRoom(client, id: '!other:example.org');
    client.rooms.addAll([room, otherRoom]);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Event declineFrom(
    Room inRoom, {
    String senderId = _me,
    String callId = 'c1',
    String msgtype = callDeclineMsgtype,
  }) => buildTestEvent(
    inRoom,
    eventId: '\$decline-$senderId-$callId-$msgtype',
    senderId: senderId,
    content: {'msgtype': msgtype, 'body': 'Call declined', 'call_id': callId},
  );

  Future<void> ring({String? roomId, String callId = 'c1'}) async {
    SystemRing.instance.set(roomId: roomId ?? room.id, callId: callId);
    await pumpEventQueue();
  }

  Future<void> sync() async {
    client.onSync.add(SyncUpdate(nextBatch: 'batch'));
    await pumpEventQueue();
  }

  Future<void> onTimeline(Event event) async {
    client.onTimelineEvent.add(event);
    await pumpEventQueue();
  }

  ProviderContainer watchRings({
    PlatformCapabilities? capabilities,
    IncomingCallPresenter? presenter,
  }) {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        if (presenter != null)
          incomingCallPresenterProvider.overrideWithValue(presenter),
      ],
    );
    addTearDown(container.dispose);
    container.read(ringElsewhereProvider);
    return container;
  }

  group('declined by me', () {
    SystemRingingCall ringing() => (roomId: room.id, callId: 'c1');

    test('is true for my decline of the ringing call in its room, whichever '
        'of my devices sent it', () {
      expect(declinedByMe(declineFrom(room), ringing()), isTrue);
    });

    test('is false for a decline by someone else', () {
      expect(
        declinedByMe(declineFrom(room, senderId: _bob), ringing()),
        isFalse,
      );
    });

    test('is false for my decline of a different call', () {
      expect(declinedByMe(declineFrom(room, callId: 'c2'), ringing()), isFalse);
    });

    test('is false for my decline in another room', () {
      expect(declinedByMe(declineFrom(otherRoom), ringing()), isFalse);
    });

    test('is false for another call message about the same call', () {
      expect(
        declinedByMe(declineFrom(room, msgtype: callInviteMsgtype), ringing()),
        isFalse,
      );
    });
  });

  group('while a call rings', () {
    late RecordingIncomingCallPresenter presenter;
    late ProviderContainer container;

    setUp(() {
      presenter = RecordingIncomingCallPresenter();
      container = watchRings(presenter: presenter);
    });

    test('my other device joining the call ends the ring here as answered '
        'elsewhere, lets it go and resolves the call', () async {
      await ring();
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.answeredElsewhere),
      ]);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
    });

    test('a ring that starts while my other device is already in the call '
        'ends right away, without waiting for a sync', () async {
      joinCall(room, userId: _me, deviceId: _laptop);

      await ring();

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.answeredElsewhere),
      ]);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
    });

    test('later syncs that still show my other device in the call end the '
        'ring only once', () async {
      await ring();
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();
      await sync();

      expect(presenter.ends, hasLength(1));
    });

    test('my other device declining the call ends the ring here as declined '
        'elsewhere, lets it go and resolves the call', () async {
      await ring();

      await onTimeline(declineFrom(room));

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.declinedElsewhere),
      ]);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
    });

    test('my other device\'s decline that decrypts late still ends the ring '
        'here', () async {
      final decryption = FakeRoomDecryption();
      client = DecryptingTestClient(decryption)..setUserId(_me);
      room = buildTestRoom(client);
      client.rooms.add(room);
      final presenter = RecordingIncomingCallPresenter();
      watchRings(presenter: presenter);
      await ring();
      final decline = declineFrom(room);
      await onTimeline(
        lockedTestEvent(room, eventId: decline.eventId, senderId: _me),
      );

      decryption.keyArrives(room, opens: decline);
      await pumpEventQueue();

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.declinedElsewhere),
      ]);
    });

    test('with nothing ringing, my other device joining or declining changes '
        'nothing', () async {
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();
      await onTimeline(declineFrom(room));

      expect(presenter.ends, isEmpty);
      expect(container.read(resolvedCallIdsProvider), isEmpty);
    });

    test('my other device in the same call id in another room leaves the '
        'ring up', () async {
      await ring();

      joinCall(otherRoom, userId: _me, deviceId: _laptop);
      await sync();

      expect(presenter.ends, isEmpty);
      expect(SystemRing.instance.ringing.value, isNotNull);
      expect(container.read(resolvedCallIdsProvider), isEmpty);
    });

    test('the caller leaving the call it rang ends the ring here as ended by '
        'them and resolves the call', () async {
      await ring();
      joinCall(room, userId: _bob, deviceId: 'BOBPHONE');
      await sync();
      expect(presenter.ends, isEmpty);

      leaveCalls(room, userId: _bob);
      await sync();

      expect(presenter.ends, [
        (roomId: room.id, callId: 'c1', end: RingEnd.remoteEnded),
      ]);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(container.read(resolvedCallIdsProvider), {'c1'});
    });

    test('a ring whose caller was never seen in the call stays up', () async {
      await ring();
      joinCall(room, userId: _bob, deviceId: 'BOBPHONE', callId: 'other');

      await sync();
      leaveCalls(room, userId: _bob);
      await sync();

      expect(presenter.ends, isEmpty);
      expect(SystemRing.instance.ringing.value, isNotNull);
    });

    test('the caller seen in another ring does not end this one', () async {
      await ring(callId: 'c0');
      joinCall(room, userId: _bob, deviceId: 'BOBPHONE', callId: 'c0');
      await sync();
      SystemRing.instance.reset();
      await ring();

      leaveCalls(room, userId: _bob);
      await sync();

      expect(presenter.ends, isEmpty);
      expect(SystemRing.instance.ringing.value, isNotNull);
    });

    test('a ring in a room this client does not know is left alone', () async {
      await ring(roomId: '!unknown:example.org');
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();

      expect(presenter.ends, isEmpty);
      expect(container.read(resolvedCallIdsProvider), isEmpty);
    });

    test('stops watching once nothing needs it', () async {
      container.dispose();
      await ring();
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();
      await onTimeline(declineFrom(room));

      expect(presenter.ends, isEmpty);
    });
  });

  group('on iOS, CallKit', () {
    late RecordedMethodCalls toNative;

    setUp(() {
      toNative = installFakeCallsChannel();
      watchRings(capabilities: iosCapabilities);
    });

    test('hears the call was answered elsewhere', () async {
      await ring();
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();

      expect(toNative.calls.map((c) => [c.method, c.arguments]), [
        [
          'endIncomingCall',
          {'roomId': room.id, 'callId': 'c1', 'reason': 'answeredElsewhere'},
        ],
      ]);
    });
  });

  group('on Android, with the ring notification up for the call', () {
    late FakeNativeRing callStyle;
    late RecordedMethodCalls toNative;

    setUp(() async {
      installSilentNotificationSideChannels();
      callStyle = installFakeCallStyleChannel();
      toNative = installFakeCallsChannel();
      await callStyle.ringNatively((
        roomId: room.id,
        callId: 'c1',
        callerId: _bob,
        isVideo: false,
      ));
      watchRings(capabilities: androidCapabilities);
    });

    Future<String?> rememberedCallId() async {
      await prefs.reload();
      return readRingingCall(prefs)?.callId;
    }

    test('my other device joining takes the notification down and forgets '
        'the call', () async {
      await ring();
      joinCall(room, userId: _me, deviceId: _laptop);

      await sync();

      expect(callStyle.calls.map((c) => c.method), ['cancelIncomingCallStyle']);
      expect(await rememberedCallId(), isNull);
      expect(toNative.calls, isEmpty);
    });
  });
}
