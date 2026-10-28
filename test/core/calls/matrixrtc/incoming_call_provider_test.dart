import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/server_ring.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';

import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  late ProviderContainer container;
  late List<IncomingCall> received;

  Event invite({
    required String eventId,
    required String senderId,
    String callId = 'call1',
    String kind = 'video',
    DateTime? at,
  }) => buildTestEvent(
    room,
    eventId: eventId,
    senderId: senderId,
    originServerTs: at ?? clock.now(),
    content: {
      'msgtype': 'im.zuno.call_invite',
      'call_id': callId,
      'kind': kind,
    },
  );

  void listen() {
    container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    received = [];
    container.listen<AsyncValue<IncomingCall>>(incomingCallProvider, (_, next) {
      final call = next.value;
      if (call != null) received.add(call);
    }, fireImmediately: true);
  }

  setUp(() {
    ringRateLimiter.clear();
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    listen();
  });

  test('rings for a fresh invite from someone else', () async {
    client.onTimelineEvent.add(
      invite(eventId: r'$1', senderId: '@bob:example.org'),
    );
    await pumpEventQueue();
    expect(received, hasLength(1));
    expect(received.single.callerId, '@bob:example.org');
    expect(received.single.kind, CallKind.video);
  });

  test(
    'ignores an invite sent by yourself (e.g. echoed back over sync)',
    () async {
      client.onTimelineEvent.add(
        invite(eventId: r'$1', senderId: '@me:example.org'),
      );
      await pumpEventQueue();
      expect(received, isEmpty);
    },
  );

  test('ignores a stale invite from a catch-up sync', () async {
    client.onTimelineEvent.add(
      invite(
        eventId: r'$1',
        senderId: '@bob:example.org',
        at: clock.now().subtract(const Duration(minutes: 5)),
      ),
    );
    await pumpEventQueue();
    expect(received, isEmpty);
  });

  test(
    'the same call_id only rings once even if the invite arrives twice',
    () async {
      client.onTimelineEvent.add(
        invite(eventId: r'$1', senderId: '@bob:example.org'),
      );
      client.onTimelineEvent.add(
        invite(eventId: r'$2', senderId: '@bob:example.org'),
      );
      await pumpEventQueue();
      expect(received, hasLength(1));
    },
  );

  test(
    'does not ring a member without permission to publish call state',
    () async {
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$powerlevels',
          senderId: '@creator:example.org',
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          content: {'state_default': 50, 'users_default': 0},
        ),
      );
      client.onTimelineEvent.add(
        invite(eventId: r'$1', senderId: '@bob:example.org'),
      );
      await pumpEventQueue();
      expect(received, isEmpty);
    },
  );

  group('a ring the server sent while the app is open', () {
    Future<void> serverRings({String caller = '@bob:example.org'}) async {
      container
          .read(serverRingsProvider)
          .add(
            ServerRing(
              roomId: room.id,
              callId: 'call1',
              callerId: caller,
              callerName: 'Bob',
              roomName: '',
              kind: CallKind.voice,
              appInFront: true,
            ),
          );
      await pumpEventQueue();
    }

    test('rings as an incoming call in its room', () async {
      client.rooms.add(room);

      await serverRings();

      expect(received.single.room, same(room));
      expect(received.single.callId, 'call1');
      expect(received.single.callerId, '@bob:example.org');
      expect(received.single.kind, CallKind.voice);
    });

    test('and the invite for the same call ring once between them', () async {
      await serverRings();
      client.onTimelineEvent.add(
        invite(eventId: r'$1', senderId: '@bob:example.org'),
      );
      await pumpEventQueue();

      expect(received, hasLength(1));
    });

    test('does not ring for a call I started', () async {
      await serverRings(caller: '@me:example.org');

      expect(received, isEmpty);
    });

    test('does not ring a member without permission to publish call '
        'state', () async {
      client.rooms.add(room);
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$powerlevels',
          senderId: '@creator:example.org',
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          content: {'state_default': 50, 'users_default': 0},
        ),
      );

      await serverRings();

      expect(received, isEmpty);
    });
  });

  group('an invite whose key arrives late', () {
    late FakeRoomDecryption decryption;

    setUp(() async {
      decryption = FakeRoomDecryption();
      client = DecryptingTestClient(decryption)..setUserId('@me:example.org');
      room = buildTestRoom(client);
      listen();
      await pumpEventQueue();
      client.onTimelineEvent.add(
        lockedTestEvent(room, eventId: r'$1', senderId: '@bob:example.org'),
      );
    });

    Future<void> keyArrives(Event opens) async {
      await pumpEventQueue();
      decryption.keyArrives(room, opens: opens);
      await pumpEventQueue();
    }

    test('rings once the key arrives', () async {
      await keyArrives(invite(eventId: r'$1', senderId: '@bob:example.org'));

      expect(received.single.callId, 'call1');
    });

    test('does not ring when it turns out to be your own', () async {
      await keyArrives(invite(eventId: r'$1', senderId: '@me:example.org'));

      expect(received, isEmpty);
    });

    test('does not ring once the invite is too old to ring', () async {
      await keyArrives(
        invite(
          eventId: r'$1',
          senderId: '@bob:example.org',
          at: clock.now().subtract(const Duration(minutes: 1)),
        ),
      );

      expect(received, isEmpty);
    });

    test('rings nothing once the app lets go of the client', () async {
      container.dispose();

      await keyArrives(invite(eventId: r'$1', senderId: '@bob:example.org'));

      expect(received, isEmpty);
    });
  });
}
