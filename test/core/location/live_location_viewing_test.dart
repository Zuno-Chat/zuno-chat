import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_viewing.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_live_location.dart';

class _ViewingClient extends LiveLocationTestClient {
  final keyQueries = <Set<String>>[];

  @override
  Future<void> updateUserDeviceKeys({Set<String>? additionalUsers}) async {
    keyQueries.add(additionalUsers ?? const {});
  }
}

class _EncryptedRoom extends Room {
  _EncryptedRoom({required super.id, required super.client});

  bool isEncrypted = true;

  @override
  bool get encrypted => isEncrypted;
}

void main() {
  const here = GeoUri(latitude: 52.5, longitude: 13.4, uncertaintyMeters: 8);
  late _ViewingClient client;
  late _EncryptedRoom room;
  late DateTime now;
  late bool offline;
  late LiveLocationViewing viewing;

  LiveLocationViewing build() => LiveLocationViewing(
    client: client,
    isOffline: () => offline,
    now: () => now,
  );

  setUp(() {
    client = _ViewingClient();
    room = _EncryptedRoom(id: '!family:x', client: client);
    client.rooms.add(room);
    now = DateTime.utc(2026, 10, 7, 12);
    for (final userId in ['@me:x', '@alex:x', '@bea:x', '@carl:x']) {
      room.setState(
        Event(
          type: EventTypes.RoomMember,
          stateKey: userId,
          senderId: userId,
          eventId: '\$joined-$userId',
          originServerTs: now,
          content: const {'membership': 'join'},
          room: room,
        ),
      );
    }
    offline = false;
    setSelfSignedTestDevices(client, '@alex:x', ['PHONE']);
    setSelfSignedTestDevices(client, '@bea:x', ['TABLET']);
    setSelfSignedTestDevices(client, '@me:x', ['MINE', 'LAPTOP']);
    viewing = build();
  });

  tearDown(() => viewing.dispose());

  void share(
    String userId, {
    String shareId = 'share1',
    String deviceId = 'PHONE',
    Duration lasting = const Duration(hours: 1),
  }) => room.setState(
    Event(
      type: liveLocationStateType,
      stateKey: userId,
      senderId: userId,
      eventId: '\$state-$userId-$shareId',
      originServerTs: now,
      content: LiveShareState(
        shareId: shareId,
        deviceId: deviceId,
        endsAt: now.add(lasting),
      ).toContent(),
      room: room,
    ),
  );

  void member(String userId, String membership) => room.setState(
    Event(
      type: EventTypes.RoomMember,
      stateKey: userId,
      senderId: userId,
      eventId: '\$member-$userId',
      originServerTs: now,
      content: {'membership': membership},
      room: room,
    ),
  );

  ToDeviceEvent position({
    String sender = '@alex:x',
    String? senderKey = 'curve-PHONE',
    String roomId = '!family:x',
    String shareId = 'share1',
    GeoUri geo = here,
    DateTime? at,
  }) => ToDeviceEvent(
    sender: sender,
    type: liveLocationPositionType,
    content: livePositionContent(
      roomId: roomId,
      shareId: shareId,
      position: LivePosition(geo: geo, at: at ?? now),
    ),
    encryptedContent: senderKey == null ? null : {'sender_key': senderKey},
  );

  Future<void> deliver(ToDeviceEvent event) async {
    client.onToDeviceEvent.add(event);
    await pumpEventQueue();
  }

  void sync() => client.onSync.add(SyncUpdate(nextBatch: 'next'));

  List<LiveToDeviceSend> watches() =>
      client.toDevice.where((m) => m.type == liveLocationWatchType).toList();

  group('positions', () {
    test('a trusted position for a live share shows', () async {
      share('@alex:x');
      final changed = viewing.changedRooms.first;

      await deliver(position());

      expect(await changed, '!family:x');
      final view = viewing.sharesIn(room).single;
      expect(view.userId, '@alex:x');
      expect(view.position?.geo, here);
      expect(view.statusAt(now), LiveShareStatus.live);
      expect(view.fromThisDevice, false);
    });

    test('ignores positions it cannot trust or place', () async {
      share('@alex:x');
      setSelfSignedTestDevices(client, '@alex:x', ['PHONE', 'WATCH']);

      for (final ignored in [
        position(senderKey: null),
        position(senderKey: 'curve-UNKNOWN'),
        position(senderKey: 'curve-WATCH'),
        position(shareId: 'other'),
        position(roomId: '!elsewhere:x'),
        position(at: now.add(const Duration(minutes: 6))),
      ]) {
        await deliver(ignored);
      }

      expect(viewing.sharesIn(room).single.position, isNull);
    });

    test('a newer position replaces an older one, never the reverse', () async {
      share('@alex:x');
      final later = now.add(const Duration(seconds: 30));
      const moved = GeoUri(latitude: 52.51, longitude: 13.4);

      await deliver(position(geo: moved, at: later));
      await deliver(position(at: now));

      expect(viewing.sharesIn(room).single.position?.geo, moved);
    });

    test(
      'a position that beats its state is shown once the state lands',
      () async {
        await deliver(position());
        expect(viewing.sharesIn(room), isEmpty);

        share('@alex:x');
        sync();
        await pumpEventQueue();

        expect(viewing.sharesIn(room).single.position?.geo, here);
      },
    );

    test('a held position is dropped after a minute', () async {
      await deliver(position());

      now = now.add(const Duration(seconds: 61));
      sync();
      await pumpEventQueue();
      share('@alex:x');
      sync();
      await pumpEventQueue();

      expect(viewing.sharesIn(room).single.position, isNull);
    });
  });

  group('the share a start message describes', () {
    LiveShareView view(String userId, String shareId) => LiveShareView(
      userId: userId,
      shareId: shareId,
      deviceId: 'PHONE',
      endsAt: now.add(const Duration(hours: 1)),
      position: null,
      fromThisDevice: false,
    );

    Event start(String senderId, {String shareId = 'share1'}) => Event(
      type: EventTypes.Message,
      senderId: senderId,
      eventId: '\$start-$senderId',
      originServerTs: now,
      content: liveLocationStartContent(
        shareId: shareId,
        endsAt: now.add(const Duration(hours: 1)),
        duration: LiveLocationDuration.hour,
      ),
      room: room,
    );

    test('is the sender\'s share with the same id', () {
      final alex = view('@alex:x', 'share1');

      expect(
        liveShareStartedBy([view('@bea:x', 'share1'), alex], start('@alex:x')),
        alex,
      );
    });

    test('is none once the sender moved on to a newer share', () {
      expect(
        liveShareStartedBy([view('@alex:x', 'newer')], start('@alex:x')),
        isNull,
      );
    });

    test('is none for a message that starts nothing', () {
      final text = Event(
        type: EventTypes.Message,
        senderId: '@alex:x',
        eventId: r'$text',
        originServerTs: now,
        content: {'msgtype': MessageTypes.Text, 'body': 'hello'},
        room: room,
      );

      expect(liveShareStartedBy([view('@alex:x', 'share1')], text), isNull);
    });
  });

  group('status', () {
    test(
      'waits, goes live, then reads as not updating after 15 minutes',
      () async {
        share('@alex:x');
        expect(
          viewing.sharesIn(room).single.statusAt(now),
          LiveShareStatus.waiting,
        );

        await deliver(position());
        final view = viewing.sharesIn(room).single;

        expect(
          view.statusAt(now.add(const Duration(minutes: 15))),
          LiveShareStatus.live,
        );
        expect(
          view.statusAt(now.add(const Duration(minutes: 15, seconds: 1))),
          LiveShareStatus.notUpdating,
        );
      },
    );

    test('a share is over at its end time', () async {
      share('@alex:x', lasting: const Duration(minutes: 15));

      now = now.add(const Duration(minutes: 15));

      expect(viewing.sharesIn(room), isEmpty);
    });

    test(
      'a share is over once its sender left, and its position goes',
      () async {
        share('@alex:x');
        await deliver(position());

        member('@alex:x', 'leave');
        sync();
        await pumpEventQueue();

        expect(viewing.sharesIn(room), isEmpty);
        member('@alex:x', 'join');
        expect(viewing.sharesIn(room).single.position, isNull);
      },
    );

    test('a share is over once its device is gone', () async {
      share('@alex:x');
      setSelfSignedTestDevices(client, '@alex:x', ['NEWPHONE']);

      expect(viewing.sharesIn(room), isEmpty);
    });

    test('an unencrypted room shows no live shares', () {
      share('@alex:x');
      room.isEncrypted = false;

      expect(viewing.sharesIn(room), isEmpty);
    });

    test('a sharer whose membership is not loaded yet is not shown', () {
      share('@alex:x');
      room.states[EventTypes.RoomMember]?.remove('@alex:x');

      expect(viewing.sharesIn(room), isEmpty);
    });

    test('someone this account blocked is neither shown nor watched', () async {
      share('@alex:x');
      client.ignored.add('@alex:x');
      await deliver(position());

      expect(viewing.sharesIn(room), isEmpty);
      final handle = viewing.watch('!family:x');
      await pumpEventQueue();
      expect(watches(), isEmpty);
      handle.close();
    });

    test('malformed or out-of-range state never breaks the room', () {
      room.setState(
        Event(
          type: liveLocationStateType,
          stateKey: '@carl:x',
          senderId: '@carl:x',
          eventId: r'$huge',
          originServerTs: now,
          content: const {'ends_ts': 9000000000000000},
          room: room,
        ),
      );
      share('@alex:x');

      expect(viewing.sharesIn(room).map((view) => view.userId), ['@alex:x']);
      expect(() => viewing.watch('!family:x').close(), returnsNormally);
    });

    test('a waiting share leaves at its end time without any sync', () {
      fakeAsync((async) {
        viewing.dispose();
        viewing = build();
        share('@alex:x', lasting: const Duration(minutes: 15));
        expect(viewing.sharesIn(room), hasLength(1));
        final changed = <String>[];
        viewing.changedRooms.listen(changed.add);

        now = now.add(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 15));

        expect(changed, contains('!family:x'));
        expect(viewing.sharesIn(room), isEmpty);
      });
    });

    test('a device found gone after the key refresh ends its share', () async {
      share('@alex:x');
      await deliver(position());
      final changed = <String>[];
      final subscription = viewing.changedRooms.listen(changed.add);

      client.onSync.add(
        SyncUpdate(
          nextBatch: 'n',
          deviceLists: DeviceListsUpdate(changed: ['@alex:x']),
        ),
      );
      setSelfSignedTestDevices(client, '@alex:x', ['NEWPHONE']);
      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
      await pumpEventQueue();

      expect(changed, contains('!family:x'));
      expect(viewing.sharesIn(room), isEmpty);
      await subscription.cancel();
    });

    test('a cleared share is over and its position goes', () async {
      share('@alex:x');
      await deliver(position());

      room.setState(
        Event(
          type: liveLocationStateType,
          stateKey: '@alex:x',
          senderId: '@alex:x',
          eventId: r'$cleared',
          originServerTs: now,
          content: const {},
          room: room,
        ),
      );
      sync();
      await pumpEventQueue();
      share('@alex:x');

      expect(viewing.sharesIn(room).single.position, isNull);
    });

    test('this device\'s own share is marked as such', () {
      share('@me:x', deviceId: 'MINE');
      share('@alex:x');

      final views = viewing.sharesIn(room);

      expect(
        {for (final view in views) view.userId: view.fromThisDevice},
        {'@me:x': true, '@alex:x': false},
      );
    });
  });

  group('refreshing once watching begins', () {
    LiveShareView alex() => viewing.sharesIn(room).single;

    test('a stale share reads as updating', () async {
      share('@alex:x');
      await deliver(position(at: now.subtract(const Duration(minutes: 4))));
      expect(alex().refreshingAt(now), isFalse);

      final handle = viewing.watch('!family:x');
      await pumpEventQueue();

      expect(alex().refreshingAt(now), isTrue);
      handle.close();
    });

    test('a fresh share does not', () async {
      share('@alex:x');
      await deliver(position(at: now.subtract(const Duration(seconds: 20))));

      final handle = viewing.watch('!family:x');
      await pumpEventQueue();

      expect(alex().refreshingAt(now), isFalse);
      handle.close();
    });

    test(
      'a stale fix arriving after watching began reads as updating too',
      () async {
        share('@alex:x');
        final handle = viewing.watch('!family:x');
        await pumpEventQueue();

        await deliver(position(at: now.subtract(const Duration(minutes: 3))));

        expect(alex().refreshingAt(now), isTrue);
        handle.close();
      },
    );

    test(
      'the first fresh fix ends it, a resend of the stale one does not',
      () async {
        share('@alex:x');
        final stale = now.subtract(const Duration(minutes: 4));
        await deliver(position(at: stale));
        final handle = viewing.watch('!family:x');
        await pumpEventQueue();

        await deliver(position(at: stale));
        expect(alex().refreshingAt(now), isTrue);

        await deliver(position(at: now));
        expect(alex().refreshingAt(now), isFalse);
        handle.close();
      },
    );

    test('gives up after two minutes without a fresh fix', () async {
      share('@alex:x');
      await deliver(position(at: now.subtract(const Duration(minutes: 4))));
      final handle = viewing.watch('!family:x');
      await pumpEventQueue();

      expect(
        alex().refreshingAt(now.add(const Duration(seconds: 119))),
        isTrue,
      );
      expect(alex().refreshingAt(now.add(const Duration(minutes: 2))), isFalse);
      handle.close();
    });

    test('once updated, a watched share ageing again does not', () async {
      share('@alex:x');
      final handle = viewing.watch('!family:x');
      await pumpEventQueue();
      await deliver(position());

      now = now.add(const Duration(minutes: 1, seconds: 30));

      expect(alex().refreshingAt(now), isFalse);
      handle.close();
    });

    test('ends with the watch', () async {
      share('@alex:x');
      await deliver(position(at: now.subtract(const Duration(minutes: 4))));
      final handle = viewing.watch('!family:x');
      await pumpEventQueue();

      handle.close();

      expect(alex().refreshingAt(now), isFalse);
    });

    test('a watch that fails to send leaves nothing updating', () async {
      share('@carl:x', deviceId: 'DESK');

      final handle = viewing.watch('!family:x');
      await pumpEventQueue();

      expect(viewing.sharesIn(room).single.refreshingSince, isNull);
      handle.close();
    });

    test('nothing reads as updating while the watch cannot go out', () async {
      share('@alex:x');
      await deliver(position(at: now.subtract(const Duration(minutes: 4))));
      offline = true;

      final handle = viewing.watch('!family:x');
      await pumpEventQueue();

      expect(alex().refreshingAt(now), isFalse);
      handle.close();
    });
  });

  group('watching', () {
    test('signals the sharing device on open, renews, and ends on close', () {
      fakeAsync((async) {
        viewing.dispose();
        viewing = build();
        share('@alex:x');
        share('@me:x', deviceId: 'MINE');

        final handle = viewing.watch('!family:x');
        async.flushMicrotasks();
        expect(watches().single.devices, ['@alex:x/PHONE']);
        expect(parseLiveWatch(watches().single.content), (
          roomId: '!family:x',
          shareId: 'share1',
          active: true,
        ));

        async.elapse(const Duration(seconds: 60));
        expect(watches(), hasLength(2));

        handle.close();
        async.flushMicrotasks();
        expect(parseLiveWatch(watches().last.content)?.active, false);

        async.elapse(const Duration(minutes: 5));
        expect(watches(), hasLength(3));
      });
    });

    test('two handles on a room share one watch', () async {
      share('@alex:x');

      final first = viewing.watch('!family:x');
      final second = viewing.watch('!family:x');
      await pumpEventQueue();
      first.close();
      await pumpEventQueue();

      expect(watches(), hasLength(1));
      second.close();
      await pumpEventQueue();
      expect(parseLiveWatch(watches().last.content)?.active, false);
    });

    test('covers a share that appears while watching', () async {
      final handle = viewing.watch('!family:x');
      await pumpEventQueue();
      expect(watches(), isEmpty);

      share('@bea:x', deviceId: 'TABLET');
      sync();
      await pumpEventQueue();

      expect(watches().single.devices, ['@bea:x/TABLET']);
      handle.close();
    });

    test('sends nothing offline and signals once back', () async {
      share('@alex:x');
      offline = true;

      final handle = viewing.watch('!family:x');
      await pumpEventQueue();
      expect(watches(), isEmpty);

      offline = false;
      viewing.onConnectivityRestored();
      await pumpEventQueue();
      expect(watches(), hasLength(1));
      handle.close();
    });

    test(
      'fetches the sharing device\'s keys when they are not known yet',
      () async {
        share('@carl:x', deviceId: 'DESK');

        final handle = viewing.watch('!family:x');
        await pumpEventQueue();

        expect(client.keyQueries, [
          {'@carl:x'},
        ]);
        expect(watches(), isEmpty);
        handle.close();
      },
    );
  });
}
