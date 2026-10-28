import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/server_ring.dart';
import 'package:zuno/core/calls/ring_identity.dart';
import 'package:zuno/core/l10n/l10n.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;

  setUp(() {
    client = buildTestClient(userId: '@me:zuno.im');
  });

  Map<String, Object?> pushed({
    String caller = '@alice:zuno.im',
    String cname = 'Alice',
    String rname = '',
    String kind = 'video',
  }) => {
    'room': '!dm:zuno.im',
    'call': 'c1',
    'caller': caller,
    'cname': cname,
    'rname': rname,
    'kind': kind,
    'ts': 1790000000000,
    'appInFront': true,
  };

  group('reading a ring native code opened', () {
    test('takes the room, call, caller, names and kind', () {
      final ring = ServerRing.from(pushed())!;

      expect(ring.roomId, '!dm:zuno.im');
      expect(ring.callId, 'c1');
      expect(ring.callerId, '@alice:zuno.im');
      expect(ring.callerName, 'Alice');
      expect(ring.roomName, '');
      expect(ring.kind, CallKind.video);
      expect(ring.appInFront, isTrue);
    });

    test('takes how long it may still ring, and nothing when native code '
        'sent no time', () {
      expect(
        ServerRing.from({...pushed(), 'ringMs': 20000})!.ringFor,
        const Duration(seconds: 20),
      );
      expect(ServerRing.from(pushed())!.ringFor, isNull);
      expect(ServerRing.from({...pushed(), 'ringMs': 'soon'})!.ringFor, isNull);
    });

    test('a voice call, or a kind it does not know, rings as voice', () {
      expect(ServerRing.from(pushed(kind: 'voice'))!.kind, CallKind.voice);
      expect(ServerRing.from(pushed(kind: 'hologram'))!.kind, CallKind.voice);
    });

    test('is nothing without a room, a call or a caller', () {
      for (final missing in ['room', 'call', 'caller']) {
        expect(ServerRing.from({...pushed(), missing: null}), isNull);
        expect(ServerRing.from({...pushed(), missing: ''}), isNull);
      }
      expect(ServerRing.from('garbage'), isNull);
    });
  });

  group('the call it rings', () {
    test('is in the room this client knows', () {
      final room = buildTestRoom(client, id: '!dm:zuno.im');
      client.rooms.add(room);

      final call = incomingCallFromServerRing(
        client,
        ServerRing.from(pushed())!,
      )!;

      expect(call.room, same(room));
      expect(call.callId, 'c1');
      expect(call.callerId, '@alice:zuno.im');
      expect(call.kind, CallKind.video);
    });

    test('rings only as long as its push allows', () {
      final call = incomingCallFromServerRing(
        client,
        ServerRing.from({...pushed(), 'ringMs': 20000})!,
      )!;

      expect(call.ringFor, const Duration(seconds: 20));
    });

    test('in a room this client does not know yet is named from the ring', () {
      final call = incomingCallFromServerRing(
        client,
        ServerRing.from(pushed(rname: 'Climbing club'))!,
      )!;

      final identity = ringIdentity(call, englishLocalizations);
      expect(identity.name, 'Climbing club');
      expect(identity.caller, 'Alice');
    });

    test('with no room name, a room it does not know is named after the '
        'caller', () {
      final call = incomingCallFromServerRing(
        client,
        ServerRing.from(pushed())!,
      )!;

      expect(ringIdentity(call, englishLocalizations).name, 'Alice');
    });

    test('is none in a room where I may not join calls', () {
      final room = buildTestRoom(client, id: '!dm:zuno.im');
      client.rooms.add(room);
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$powerlevels',
          senderId: '@creator:zuno.im',
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          content: {'state_default': 50, 'users_default': 0},
        ),
      );

      expect(
        incomingCallFromServerRing(client, ServerRing.from(pushed())!),
        isNull,
      );
    });

    test('is none for a call I started myself', () {
      expect(
        incomingCallFromServerRing(
          client,
          ServerRing.from(pushed(caller: '@me:zuno.im'))!,
        ),
        isNull,
      );
    });
  });
}
