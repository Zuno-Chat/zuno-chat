import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';

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
    originServerTs: at ?? DateTime.now(),
    content: {
      'msgtype': 'im.zuno.call_invite',
      'call_id': callId,
      'kind': kind,
    },
  );

  setUp(() {
    ringRateLimiter.clear();
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    received = [];
    container.listen<AsyncValue<IncomingCall>>(incomingCallProvider, (_, next) {
      final call = next.value;
      if (call != null) received.add(call);
    }, fireImmediately: true);
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
        at: DateTime.now().subtract(const Duration(minutes: 5)),
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
}
