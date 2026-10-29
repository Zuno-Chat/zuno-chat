import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_changes.dart';

import '../../helpers/fake_matrix.dart';

const roomId = '!room:example.org';
const otherId = '!other:example.org';

SyncUpdate joined(String id, JoinedRoomUpdate update) => SyncUpdate(
  nextBatch: 's1',
  rooms: RoomsUpdate(join: {id: update}),
);

MatrixEvent stateEvent(String type) => MatrixEvent(
  eventId: r'$state',
  type: type,
  senderId: '@bob:example.org',
  originServerTs: DateTime(2026),
  stateKey: '',
  content: const {},
);

MatrixEvent message() => MatrixEvent(
  eventId: r'$message',
  type: EventTypes.Message,
  senderId: '@bob:example.org',
  originServerTs: DateTime(2026),
  content: const {'msgtype': 'm.text', 'body': 'hi'},
);

void main() {
  group('syncTouchesRoom', () {
    for (final (membership, rooms) in [
      ('joined', RoomsUpdate(join: {roomId: JoinedRoomUpdate()})),
      ('invited', RoomsUpdate(invite: {roomId: InvitedRoomUpdate()})),
      ('left', RoomsUpdate(leave: {roomId: LeftRoomUpdate()})),
    ]) {
      test('a $membership entry for the room touches it', () {
        final update = SyncUpdate(nextBatch: 's1', rooms: rooms);
        expect(syncTouchesRoom(update, roomId), isTrue);
      });
    }

    test('another room or no rooms does not', () {
      expect(syncTouchesRoom(SyncUpdate(nextBatch: 's1'), roomId), isFalse);
      expect(
        syncTouchesRoom(joined(otherId, JoinedRoomUpdate()), roomId),
        isFalse,
      );
    });
  });

  group('syncChangesRoomState', () {
    test('state, a state event in the timeline, a summary with content, '
        'direct chats or a membership change does', () {
      for (final update in [
        joined(
          roomId,
          JoinedRoomUpdate(state: [stateEvent(EventTypes.RoomName)]),
        ),
        joined(
          roomId,
          JoinedRoomUpdate(
            timeline: TimelineUpdate(
              events: [stateEvent(EventTypes.RoomTopic)],
            ),
          ),
        ),
        joined(
          roomId,
          JoinedRoomUpdate(
            summary: RoomSummary.fromJson(const {'m.joined_member_count': 2}),
          ),
        ),
        SyncUpdate(
          nextBatch: 's1',
          accountData: [
            BasicEvent(
              type: 'm.direct',
              content: const {
                '@bob:example.org': [roomId],
              },
            ),
          ],
        ),
        SyncUpdate(
          nextBatch: 's1',
          rooms: RoomsUpdate(leave: {roomId: LeftRoomUpdate()}),
        ),
      ]) {
        expect(syncChangesRoomState(update, roomId), isTrue);
      }
    });

    test('an empty summary, other account data, a message, a receipt or '
        'another room does not', () {
      expect(
        syncChangesRoomState(
          joined(
            roomId,
            JoinedRoomUpdate(summary: RoomSummary.fromJson(const {})),
          ),
          roomId,
        ),
        isFalse,
      );
      expect(
        syncChangesRoomState(
          SyncUpdate(
            nextBatch: 's1',
            accountData: [BasicEvent(type: 'im.zuno.other', content: const {})],
          ),
          roomId,
        ),
        isFalse,
      );
      expect(
        syncChangesRoomState(
          joined(
            roomId,
            JoinedRoomUpdate(timeline: TimelineUpdate(events: [message()])),
          ),
          roomId,
        ),
        isFalse,
      );
      expect(
        syncChangesRoomState(
          joined(
            roomId,
            JoinedRoomUpdate(
              ephemeral: [BasicEvent(type: 'm.receipt', content: const {})],
            ),
          ),
          roomId,
        ),
        isFalse,
      );
      expect(
        syncChangesRoomState(
          joined(
            otherId,
            JoinedRoomUpdate(state: [stateEvent(EventTypes.RoomName)]),
          ),
          roomId,
        ),
        isFalse,
      );
    });
  });

  group('RoomChangesBuilder', () {
    late Client client;
    late Room room;
    late Room other;
    late int builds;

    setUp(() {
      client = buildTestClient(userId: '@me:example.org');
      room = buildTestRoom(client);
      other = buildTestRoom(client, id: otherId);
      builds = 0;
    });

    void rename(Room target, String name) => target.setState(
      buildTestEvent(
        target,
        eventId: '\$name-$name',
        senderId: '@bob:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': name},
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    Widget counted(RoomChanges changes) => RoomChangesBuilder(
      changes: changes,
      builder: (_) {
        builds++;
        return const SizedBox();
      },
    );

    testWidgets('a burst of this room\'s state rebuilds once', (tester) async {
      await tester.pumpWidget(counted(RoomChanges.state(room)));
      builds = 0;

      rename(room, 'a');
      rename(room, 'b');
      await settle(tester);

      expect(builds, 1);
    });

    testWidgets('another room\'s state and a plain message leave it alone', (
      tester,
    ) async {
      await tester.pumpWidget(counted(RoomChanges.state(room)));
      builds = 0;

      rename(other, 'a');
      client.onSync.add(
        joined(
          roomId,
          JoinedRoomUpdate(timeline: TimelineUpdate(events: [message()])),
        ),
      );
      await settle(tester);

      expect(builds, 0);
    });

    testWidgets('any change in the room includes a receipt', (tester) async {
      await tester.pumpWidget(counted(RoomChanges.any(room)));
      builds = 0;

      client.onSync.add(
        joined(
          roomId,
          JoinedRoomUpdate(
            ephemeral: [BasicEvent(type: 'm.receipt', content: const {})],
          ),
        ),
      );
      await settle(tester);

      expect(builds, 1);
    });

    testWidgets('while covered it waits, then rebuilds once on return', (
      tester,
    ) async {
      final inFront = ValueNotifier(false);
      addTearDown(inFront.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: inFront,
          builder: (_, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
          child: RoomChangesBuilder(
            changes: RoomChanges.state(room),
            builder: (_) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      );
      builds = 0;

      rename(room, 'a');
      await settle(tester);
      rename(room, 'b');
      await settle(tester);
      expect(builds, 0);

      inFront.value = true;
      await settle(tester);
      expect(builds, 1);

      await settle(tester);
      expect(builds, 1);
    });

    testWidgets('onChange runs before the rebuild', (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(
        RoomChangesBuilder(
          changes: RoomChanges.state(room),
          onChange: () => seen.add(builds),
          builder: (_) {
            builds++;
            return const SizedBox();
          },
        ),
      );

      rename(room, 'a');
      await settle(tester);

      expect(seen, [1]);
      expect(builds, 2);
    });

    testWidgets('the same changes keep one subscription across rebuilds', (
      tester,
    ) async {
      await tester.pumpWidget(counted(RoomChanges.state(room)));
      await tester.pumpWidget(counted(RoomChanges.state(room)));
      builds = 0;

      rename(room, 'a');
      await settle(tester);

      expect(builds, 1);
    });
  });
}
