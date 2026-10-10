import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/live_location_availability.dart';
import 'package:zuno/core/location/live_location_capture.dart';
import 'package:zuno/core/location/live_location_notice.dart';
import 'package:zuno/core/location/live_location_policy.dart';
import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/core/location/live_location_recipients.dart';
import 'package:zuno/core/location/live_location_sharing.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_live_location.dart';

void main() {
  const here = GeoUri(latitude: 52.5, longitude: 13.4, uncertaintyMeters: 3);
  late LiveLocationTestClient client;
  late LiveLocationTestRoom room;
  late FakeLiveLocationCapture capture;
  late DateTime now;
  late bool offline;
  late List<DeviceKeys> recipients;
  late LiveLocationSharing sharing;

  GeoUri northBy(double meters) => GeoUri(
    latitude: here.latitude + meters / 111319.49,
    longitude: here.longitude,
    uncertaintyMeters: 3,
  );

  LivePosition at(GeoUri geo) => LivePosition(geo: geo, at: now);

  void member(LiveLocationTestRoom target, String userId, String membership) =>
      target.setState(
        Event(
          type: EventTypes.RoomMember,
          stateKey: userId,
          senderId: userId,
          eventId: '\$member-$userId-$membership',
          originServerTs: now,
          content: {'membership': membership},
          room: target,
        ),
      );

  LiveLocationTestRoom addRoom(String id) {
    final added = LiveLocationTestRoom(id: id, client: client);
    client.rooms.add(added);
    for (final userId in ['@me:x', '@alex:x', '@bea:x']) {
      member(added, userId, 'join');
    }
    return added;
  }

  LiveLocationSharing build() => LiveLocationSharing(
    client: client,
    capture: capture,
    isOffline: () => offline,
    recipients: (_) async => recipients,
    now: () => now,
  );

  setUp(() {
    client = LiveLocationTestClient();
    now = DateTime.utc(2026, 10, 7, 12);
    room = addRoom('!family:x');
    capture = FakeLiveLocationCapture();
    offline = false;
    setSelfSignedTestDevices(client, '@alex:x', ['PHONE']);
    setSelfSignedTestDevices(client, '@bea:x', ['TABLET']);
    setSelfSignedTestDevices(client, '@eve:x', ['LAPTOP']);
    recipients = [
      client.userDeviceKeys['@alex:x']!.deviceKeys['PHONE']!,
      client.userDeviceKeys['@bea:x']!.deviceKeys['TABLET']!,
    ];
    sharing = build();
  });

  tearDown(() => sharing.dispose());

  ToDeviceEvent watch({
    String sender = '@bea:x',
    String? senderKey = 'curve-TABLET',
    String roomId = '!family:x',
    String? shareId,
    bool active = true,
  }) => ToDeviceEvent(
    sender: sender,
    type: liveLocationWatchType,
    content: liveWatchContent(
      roomId: roomId,
      shareId: shareId ?? sharing.shares.value.single.shareId,
      active: active,
    ),
    encryptedContent: senderKey == null ? null : {'sender_key': senderKey},
  );

  void sync({
    String? roomId,
    List<MatrixEvent> state = const [],
    List<MatrixEvent> timeline = const [],
  }) => client.onSync.add(
    SyncUpdate(
      nextBatch: 'batch',
      rooms: roomId == null
          ? null
          : RoomsUpdate(
              join: {
                roomId: JoinedRoomUpdate(
                  state: state,
                  timeline: TimelineUpdate(events: timeline),
                ),
              },
            ),
    ),
  );

  MatrixEvent ownStateEvent(
    Map<String, Object?> content, {
    String id = r'$s',
  }) => MatrixEvent(
    type: liveLocationStateType,
    stateKey: '@me:x',
    senderId: '@me:x',
    eventId: id,
    originServerTs: now,
    content: content,
  );

  void ownShareFrom(
    String deviceId, {
    String shareId = 'old',
    Duration lasting = const Duration(hours: 1),
  }) {
    final content = LiveShareState(
      shareId: shareId,
      deviceId: deviceId,
      endsAt: now.add(lasting),
    ).toContent();
    client.serverState[room.id] = content;
    room.setState(
      Event(
        type: liveLocationStateType,
        stateKey: '@me:x',
        senderId: '@me:x',
        eventId: '\$own-$shareId',
        originServerTs: now,
        content: content,
        room: room,
      ),
    );
  }

  Future<void> startSharing({
    LiveLocationTestRoom? into,
    LiveLocationDuration duration = LiveLocationDuration.hour,
  }) async {
    await sharing.start(into ?? room, duration, at(here));
    await pumpEventQueue();
  }

  List<LiveToDeviceSend> positions() =>
      client.toDevice.where((m) => m.type == liveLocationPositionType).toList();

  group('starting', () {
    test(
      'publishes the share, announces it and sends the first position',
      () async {
        await startSharing();

        final share = sharing.shares.value.single;
        expect(share.roomId, '!family:x');
        expect(share.endsAt, now.add(const Duration(hours: 1)));
        expect(capture.mode, LiveLocationMode.coarse);
        expect(capture.notice?.text, 'In Family');
        expect(client.stateWrites.single.stateKey, '@me:x');
        expect(client.stateWrites.single.content, {
          'share_id': share.shareId,
          'device_id': 'MINE',
          'ends_ts': share.endsAt.millisecondsSinceEpoch,
        });
        expect(room.sent.single['msgtype'], liveLocationMsgtype);
        expect(room.sent.single['share_id'], share.shareId);
        expect(positions().single.devices, ['@alex:x/PHONE', '@bea:x/TABLET']);
        expect(
          parseLivePosition(positions().single.content)?.position.geo,
          here,
        );
        expect(sharing.isSharingIn('!family:x'), true);
        expect(liveShareStateOf(room, '@me:x')?.shareId, share.shareId);
      },
    );

    test('is refused where the room does not allow it', () async {
      room.allowState = false;

      await expectLater(
        sharing.start(room, LiveLocationDuration.hour, at(here)),
        throwsA(
          isA<LiveShareStartException>().having(
            (e) => e.reason,
            'reason',
            LiveShareStartFailure.notAllowed,
          ),
        ),
      );
      expect(capture.calls, isEmpty);
      expect(client.stateWrites, isEmpty);
    });

    test('is refused while this device already shares there', () async {
      await startSharing();

      await expectLater(
        sharing.start(room, LiveLocationDuration.hour, at(here)),
        throwsA(
          isA<LiveShareStartException>().having(
            (e) => e.reason,
            'reason',
            LiveShareStartFailure.alreadySharing,
          ),
        ),
      );
    });

    test('fails cleanly when capture cannot start', () async {
      capture.startError = const LiveCaptureUnavailable();

      await expectLater(
        sharing.start(room, LiveLocationDuration.hour, at(here)),
        throwsA(
          isA<LiveShareStartException>().having(
            (e) => e.reason,
            'reason',
            LiveShareStartFailure.captureUnavailable,
          ),
        ),
      );
      expect(client.stateWrites, isEmpty);
      expect(sharing.shares.value, isEmpty);
      expect(sharing.needsSync.value, false);
    });

    test('stops capture again when the server refuses the state', () async {
      client.stateWriteError = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'no',
      });

      await expectLater(
        sharing.start(room, LiveLocationDuration.hour, at(here)),
        throwsA(
          isA<LiveShareStartException>().having(
            (e) => e.reason,
            'reason',
            LiveShareStartFailure.notAllowed,
          ),
        ),
      );
      expect(capture.calls, ['start', 'stop']);
      expect(sharing.shares.value, isEmpty);
      expect(room.sent, isEmpty);
    });

    test('keeps sync needed from the moment a share starts', () async {
      client.holdStateWrites = Completer();

      final starting = sharing.start(room, LiveLocationDuration.hour, at(here));
      await pumpEventQueue();
      expect(sharing.needsSync.value, true);
      expect(sharing.shares.value, isEmpty);

      client.holdStateWrites!.complete();
      client.holdStateWrites = null;
      await starting;
      expect(sharing.shares.value, hasLength(1));
    });

    test('sends nothing before its state is published', () async {
      client.holdStateWrites = Completer();
      final starting = sharing.start(room, LiveLocationDuration.hour, at(here));
      await pumpEventQueue();

      capture.fix(at(northBy(500)), 1);
      await pumpEventQueue();
      expect(positions(), isEmpty);

      client.holdStateWrites!.complete();
      client.holdStateWrites = null;
      await starting;
      await pumpEventQueue();
      expect(positions(), hasLength(1));
    });

    test('a stop during start lands after the publish, never before', () async {
      client.holdStateWrites = Completer();
      final starting = sharing.start(room, LiveLocationDuration.hour, at(here));
      await pumpEventQueue();

      final stopping = sharing.stop('!family:x');
      client.holdStateWrites!.complete();
      client.holdStateWrites = null;
      await starting;
      await stopping;

      expect(client.stateWrites.map((w) => w.content.isEmpty), [false, true]);
      expect(liveShareStateOf(room, '@me:x'), isNull);
    });
  });

  group('sending', () {
    test('follows the policy and releases each fix\'s wake lock', () async {
      await startSharing();
      final start = now;

      now = start.add(const Duration(seconds: 30));
      capture.fix(at(northBy(20)), 1);
      await pumpEventQueue();
      expect(positions(), hasLength(1));
      expect(capture.released, [1]);

      now = start.add(const Duration(minutes: 5));
      capture.fix(at(northBy(20)), 2);
      await pumpEventQueue();
      expect(positions(), hasLength(2));
      expect(positions().last.devices, ['@alex:x/PHONE', '@bea:x/TABLET']);
      expect(capture.released, [1, 2]);
    });

    test(
      'a watcher gets a position at once, then precise updates alone',
      () async {
        await startSharing();
        final start = now;

        client.onToDeviceEvent.add(watch());
        await pumpEventQueue();
        expect(capture.mode, LiveLocationMode.precise);
        expect(positions().last.devices, ['@bea:x/TABLET']);

        now = start.add(const Duration(seconds: 6));
        capture.fix(at(northBy(15)), 1);
        await pumpEventQueue();
        expect(positions(), hasLength(3));
        expect(positions().last.devices, ['@bea:x/TABLET']);
      },
    );

    test(
      'drops back to coarse only after half a minute with no watcher',
      () async {
        await startSharing();
        final start = now;
        client.onToDeviceEvent.add(watch());
        await pumpEventQueue();

        client.onToDeviceEvent.add(watch(active: false));
        await pumpEventQueue();
        expect(capture.mode, LiveLocationMode.precise);

        now = start.add(const Duration(seconds: 31));
        capture.fix(at(northBy(1)), 1);
        await pumpEventQueue();
        expect(capture.mode, LiveLocationMode.coarse);
      },
    );

    test('a watch lapses two minutes after its last renewal', () async {
      await startSharing();
      final start = now;
      client.onToDeviceEvent.add(watch());
      await pumpEventQueue();

      now = start.add(const Duration(minutes: 2, seconds: 1));
      capture.fix(at(northBy(1)), 1);
      await pumpEventQueue();
      now = start.add(const Duration(minutes: 2, seconds: 32));
      capture.fix(at(northBy(2)), 2);
      await pumpEventQueue();

      expect(capture.mode, LiveLocationMode.coarse);
    });

    test(
      'toggling a watch cannot force sends faster than five seconds',
      () async {
        await startSharing();

        for (var i = 0; i < 4; i++) {
          client.onToDeviceEvent.add(watch());
          client.onToDeviceEvent.add(watch(active: false));
        }
        client.onToDeviceEvent.add(watch());
        await pumpEventQueue();

        expect(
          positions().where((m) => m.devices.join() == '@bea:x/TABLET'),
          hasLength(1),
        );
      },
    );

    test('ignores watches it cannot trust or place', () async {
      await startSharing();

      for (final ignored in [
        watch(senderKey: null),
        watch(sender: '@eve:x', senderKey: 'curve-LAPTOP'),
        watch(shareId: 'another-share'),
        watch(roomId: '!other:x'),
      ]) {
        client.onToDeviceEvent.add(ignored);
      }
      await pumpEventQueue();

      expect(capture.mode, LiveLocationMode.coarse);
      expect(positions(), hasLength(1));
    });

    test('a removed member stops receiving at once', () async {
      await startSharing();
      final start = now;
      client.onToDeviceEvent.add(watch());
      await pumpEventQueue();

      member(room, '@bea:x', 'ban');
      sync(roomId: '!family:x');
      await pumpEventQueue();
      now = start.add(const Duration(minutes: 6));
      capture.fix(at(northBy(300)), 1);
      await pumpEventQueue();

      expect(positions().last.devices, ['@alex:x/PHONE']);
    });

    test('someone this account blocked never receives or watches', () async {
      client.ignored.add('@bea:x');
      await startSharing();

      client.onToDeviceEvent.add(watch());
      await pumpEventQueue();

      expect(positions().single.devices, ['@alex:x/PHONE']);
      expect(capture.mode, LiveLocationMode.coarse);
    });

    test('sends nothing offline and the newest position once back', () async {
      await startSharing();
      final start = now;
      offline = true;

      now = start.add(const Duration(minutes: 5));
      capture.fix(at(northBy(300)), 1);
      now = start.add(const Duration(minutes: 6));
      capture.fix(at(northBy(600)), 2);
      await pumpEventQueue();
      expect(positions(), hasLength(1));
      expect(capture.released, [1, 2]);

      offline = false;
      sharing.onConnectivityRestored();
      await pumpEventQueue();

      expect(positions(), hasLength(2));
      expect(
        parseLivePosition(positions().last.content)?.position.geo.toUriString(),
        northBy(600).toUriString(),
      );
    });

    test(
      'a failed send waits for its next turn, or for the connection',
      () async {
        await startSharing();
        final start = now;
        client.sendError = Exception('unreachable');

        now = start.add(const Duration(minutes: 5));
        capture.fix(at(northBy(10)), 1);
        await pumpEventQueue();
        now = start.add(const Duration(minutes: 5, seconds: 30));
        capture.fix(at(northBy(20)), 2);
        await pumpEventQueue();
        expect(positions(), hasLength(1));

        client.sendError = null;
        sharing.onConnectivityRestored();
        await pumpEventQueue();
        expect(positions(), hasLength(2));
      },
    );

    test(
      'keeps one send in flight and sends only the newest after it',
      () async {
        await startSharing();
        final start = now;
        client.holdSends = Completer();

        now = start.add(const Duration(minutes: 5));
        capture.fix(at(northBy(300)), 1);
        await pumpEventQueue();
        now = start.add(const Duration(minutes: 11));
        capture.fix(at(northBy(600)), 2);
        capture.fix(at(northBy(900)), 3);
        await pumpEventQueue();
        expect(capture.released, isEmpty);

        client.holdSends!.complete();
        client.holdSends = null;
        await pumpEventQueue();

        expect(
          positions()
              .skip(1)
              .map(
                (m) => parseLivePosition(m.content)?.position.geo.toUriString(),
              ),
          [northBy(300).toUriString(), northBy(900).toUriString()],
        );
        expect(capture.released, [1, 2, 3]);
      },
    );

    test('a clock moved back does not stall newer fixes', () async {
      await startSharing();
      final start = now;
      capture.fix(at(northBy(1)), 1);
      await pumpEventQueue();

      now = start.subtract(const Duration(minutes: 20));
      capture.fix(at(northBy(500)), 2);
      await pumpEventQueue();

      expect(
        parseLivePosition(positions().last.content)?.position.geo.toUriString(),
        northBy(500).toUriString(),
      );
    });
  });

  group('stopping', () {
    test('clears the state before capture stops, then sends nothing', () async {
      await startSharing();

      await sharing.stop('!family:x');
      capture.fix(at(northBy(500)), 1);
      await pumpEventQueue();

      expect(client.stateWrites.last.content, isEmpty);
      expect(capture.calls.last, 'stop');
      expect(sharing.shares.value, isEmpty);
      expect(sharing.needsSync.value, false);
      expect(positions(), hasLength(1));
      expect(liveShareStateOf(room, '@me:x'), isNull);
    });

    test(
      'keeps capture running while the clear is still being written',
      () async {
        await startSharing();
        client.holdStateWrites = Completer();

        final stopping = sharing.stop('!family:x');
        await pumpEventQueue();
        expect(capture.running, true);

        client.holdStateWrites!.complete();
        client.holdStateWrites = null;
        await stopping;
        expect(capture.running, false);
      },
    );

    test('several shares run on one capture until the last stops', () async {
      final other = addRoom('!alex:x')
        ..direct = true
        ..title = 'Alex';
      await startSharing();
      await startSharing(into: other);

      expect(capture.calls.where((c) => c == 'start'), hasLength(1));
      expect(capture.notice?.text, 'In 1 chat and 1 room');

      await sharing.stop('!family:x');
      expect(capture.running, true);
      expect(capture.notice?.text, 'With Alex');

      await sharing.stop('!alex:x');
      expect(capture.running, false);
    });

    test('ends when its time is up', () {
      fakeAsync((async) {
        sharing.dispose();
        sharing = build();
        unawaited(
          sharing.start(room, LiveLocationDuration.quarterHour, at(here)),
        );
        async.flushMicrotasks();
        expect(sharing.shares.value, hasLength(1));

        now = now.add(const Duration(minutes: 15));
        async.elapse(const Duration(minutes: 15));

        expect(sharing.shares.value, isEmpty);
        expect(client.stateWrites.last.content, isEmpty);
      });
    });

    test('ends by the wall clock even when its timer is late', () async {
      await startSharing(duration: LiveLocationDuration.quarterHour);

      now = now.add(const Duration(minutes: 16));
      capture.fix(at(northBy(300)), 1);
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
      expect(positions(), hasLength(1));
      expect(client.stateWrites.last.content, isEmpty);
    });

    test('ends without writing when the server shows it replaced', () async {
      await startSharing();
      final writes = client.stateWrites.length;
      client.serverState['!family:x'] = {
        'share_id': 'newer',
        'device_id': 'LAPTOP',
        'ends_ts': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      };

      sync(roomId: '!family:x', timeline: [ownStateEvent({})]);
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites, hasLength(writes));
    });

    test(
      'keeps going when a late echo is older than the server state',
      () async {
        await startSharing();

        sync(
          roomId: '!family:x',
          timeline: [ownStateEvent({}, id: r'$older')],
        );
        await pumpEventQueue();

        expect(client.serverStateReads, ['!family:x']);
        expect(sharing.shares.value, hasLength(1));
      },
    );

    test('ends without writing once this account left the room', () async {
      await startSharing();
      final writes = client.stateWrites.length;
      room.membership = Membership.leave;

      sync(roomId: '!family:x');
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites, hasLength(writes));
    });

    MatrixEvent redaction(String redacts) => MatrixEvent(
      type: EventTypes.Redaction,
      senderId: '@me:x',
      eventId: r'$redaction',
      originServerTs: now,
      redacts: redacts,
      content: const {},
    );

    test('stops when its start message is deleted', () async {
      await startSharing();

      sync(roomId: '!family:x', timeline: [redaction(r'$start-!family:x')]);
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites.last.content, isEmpty);
    });

    test('a resent start message also stops the share when deleted', () async {
      room.sendFails = true;
      await startSharing();
      client.onTimelineEvent.add(
        Event(
          type: EventTypes.Message,
          senderId: '@me:x',
          eventId: r'$resent',
          originServerTs: now,
          content: room.sent.single,
          room: room,
        ),
      );
      await pumpEventQueue();

      sync(roomId: '!family:x', timeline: [redaction(r'$resent')]);
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
    });

    test('stops every share when location is lost', () async {
      await startSharing();
      final lost = sharing.captureLost.first;

      capture.lose(LiveCaptureFailure.denied);
      await pumpEventQueue();

      expect(await lost, LiveCaptureFailure.denied);
      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites.last.content, isEmpty);
    });

    test('a capture that ended on its own stops quietly', () async {
      await startSharing();
      var reported = false;
      final subscription = sharing.captureLost.listen((_) => reported = true);

      capture.lose(LiveCaptureFailure.ended);
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
      expect(reported, false);
      await subscription.cancel();
    });

    test('stops every share from the notification', () async {
      await startSharing();

      capture.requestStop();
      await pumpEventQueue();

      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites.last.content, isEmpty);
    });

    test('stopping everything is bounded when the server hangs', () {
      fakeAsync((async) {
        sharing.dispose();
        sharing = build();
        unawaited(sharing.start(room, LiveLocationDuration.hour, at(here)));
        async.flushMicrotasks();
        client.holdStateWrites = Completer();
        var done = false;

        unawaited(
          sharing
              .stopAll(within: const Duration(seconds: 5))
              .then((_) => done = true),
        );
        async.elapse(const Duration(seconds: 6));

        expect(done, true);
        expect(sharing.shares.value, isEmpty);
        expect(capture.running, false);
      });
    });
  });

  group('stopping from here', () {
    test('stops this device\'s share', () async {
      await startSharing();

      await sharing.stopIn('!family:x');

      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites.last.content, isEmpty);
    });

    test('ends a share this account runs on another device', () async {
      ownShareFrom('LAPTOP', shareId: 'elsewhere');

      await sharing.stopIn('!family:x');

      expect(client.stateWrites.single.content, isEmpty);
      expect(liveShareStateOf(room, '@me:x'), isNull);
    });
  });

  group('before its start message is deleted', () {
    Event startMessage({String sender = '@me:x', String? shareId}) => Event(
      type: EventTypes.Message,
      senderId: sender,
      eventId: r'$start',
      originServerTs: now,
      content: liveLocationStartContent(
        shareId: shareId ?? sharing.shares.value.single.shareId,
        endsAt: now.add(const Duration(hours: 1)),
        duration: LiveLocationDuration.hour,
      ),
      room: room,
    );

    test('stops this device\'s share', () async {
      await startSharing();

      await sharing.stopShareStartedBy(startMessage());

      expect(sharing.shares.value, isEmpty);
      expect(client.stateWrites.last.content, isEmpty);
    });

    test('ends the share this account runs on another device', () async {
      ownShareFrom('LAPTOP', shareId: 'elsewhere');

      await sharing.stopShareStartedBy(startMessage(shareId: 'elsewhere'));

      expect(client.stateWrites.single.content, isEmpty);
    });

    test('someone else\'s start message stops nothing', () async {
      await startSharing();
      final writes = client.stateWrites.length;

      await sharing.stopShareStartedBy(startMessage(sender: '@alex:x'));

      expect(sharing.shares.value, hasLength(1));
      expect(client.stateWrites, hasLength(writes));
    });

    test('an older start message of mine stops nothing', () async {
      await startSharing();
      final writes = client.stateWrites.length;

      await sharing.stopShareStartedBy(startMessage(shareId: 'older'));

      expect(sharing.shares.value, hasLength(1));
      expect(client.stateWrites, hasLength(writes));
    });
  });

  group('leftovers from an earlier run', () {
    test('an open share naming this device is cleared once', () async {
      sharing.dispose();
      ownShareFrom('MINE');

      sharing = build();
      await pumpEventQueue();
      sync();
      await pumpEventQueue();

      expect(client.stateWrites, hasLength(1));
      expect(client.stateWrites.single.content, isEmpty);
    });

    test('an expired leftover is left alone', () async {
      sharing.dispose();
      ownShareFrom('MINE', lasting: const Duration(minutes: -1));

      sharing = build();
      await pumpEventQueue();

      expect(client.stateWrites, isEmpty);
    });

    test('a refused clear is not retried until permissions change', () async {
      sharing.dispose();
      ownShareFrom('MINE');
      client.stateWriteError = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'no',
      });

      sharing = build();
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 2));
      sync();
      await pumpEventQueue();
      expect(client.serverStateReads, hasLength(1));

      room.setState(
        Event(
          type: EventTypes.RoomPowerLevels,
          stateKey: '',
          senderId: '@admin:x',
          eventId: r'$power',
          originServerTs: now,
          content: const {},
          room: room,
        ),
      );
      now = now.add(const Duration(minutes: 2));
      sync();
      await pumpEventQueue();
      expect(client.serverStateReads, hasLength(2));
    });

    test('a share from another of my devices is left alone', () async {
      sharing.dispose();
      ownShareFrom('LAPTOP');

      sharing = build();
      await pumpEventQueue();

      expect(client.stateWrites, isEmpty);
    });

    test('after rejoining, a share left over from before is cleared', () async {
      ownShareFrom('LAPTOP');

      sync(
        roomId: '!family:x',
        timeline: [
          MatrixEvent(
            type: EventTypes.RoomMember,
            stateKey: '@me:x',
            senderId: '@me:x',
            eventId: r'$rejoin',
            originServerTs: now,
            content: const {'membership': 'join'},
            unsigned: const {
              'prev_content': {'membership': 'leave'},
            },
          ),
        ],
      );
      await pumpEventQueue();

      expect(client.stateWrites.single.content, isEmpty);
    });

    test('a profile change while joined is not taken for a rejoin', () async {
      ownShareFrom('LAPTOP');

      sync(
        roomId: '!family:x',
        timeline: [
          MatrixEvent(
            type: EventTypes.RoomMember,
            stateKey: '@me:x',
            senderId: '@me:x',
            eventId: r'$rename',
            originServerTs: now,
            content: const {'membership': 'join', 'displayname': 'Me'},
            unsigned: const {
              'prev_content': {'membership': 'join'},
            },
          ),
        ],
      );
      await pumpEventQueue();

      expect(client.stateWrites, isEmpty);
    });
  });

  group('notice', () {
    test('names the chat, the room, or counts them', () {
      final alex = addRoom('!alex:x')
        ..direct = true
        ..title = 'Alex';
      final bea = addRoom('!bea:x')
        ..direct = true
        ..title = 'Bea';
      final ends = now.add(const Duration(hours: 1));
      final later = now.add(const Duration(hours: 2));

      final chat = liveLocationNotice([(room: alex, endsAt: ends)]);
      expect(chat.title, 'Sharing live location');
      expect(chat.text, 'With Alex');
      expect(chat.roomId, '!alex:x');
      expect(chat.endsAt, ends);

      expect(
        liveLocationNotice([(room: room, endsAt: ends)]).text,
        'In Family',
      );

      final several = liveLocationNotice([
        (room: alex, endsAt: ends),
        (room: bea, endsAt: later),
        (room: room, endsAt: ends),
      ]);
      expect(several.text, 'In 2 chats and 1 room');
      expect(several.roomId, isNull);
      expect(several.endsAt, later);
    });
  });

  group('who may receive', () {
    test('joined, trusted, not blocked, and never this device', () {
      setSelfSignedTestDevices(client, '@me:x', ['MINE', 'LAPTOP']);
      setTestDevices(client, '@carl:x', {'UNSIGNED': null});
      member(room, '@carl:x', 'join');
      member(room, '@eve:x', 'invite');
      client.ignored.add('@bea:x');
      final ignored = client.ignoredUsers.toSet();

      bool peer(String userId, String deviceId) => isLiveLocationPeer(
        room,
        client.userDeviceKeys[userId]!.deviceKeys[deviceId]!,
        ignored: ignored,
      );

      expect(peer('@me:x', 'LAPTOP'), true);
      expect(peer('@alex:x', 'PHONE'), true);
      expect(peer('@me:x', 'MINE'), false);
      expect(peer('@bea:x', 'TABLET'), false);
      expect(peer('@carl:x', 'UNSIGNED'), false);
      expect(peer('@eve:x', 'LAPTOP'), false);
    });

    test('a member whose membership is not loaded is not a peer', () {
      room.states[EventTypes.RoomMember]?.remove('@alex:x');

      expect(
        isLiveLocationPeer(
          room,
          client.userDeviceKeys['@alex:x']!.deviceKeys['PHONE']!,
          ignored: const {},
        ),
        false,
      );
    });

    test('an unencrypted room cannot share live location', () {
      final open = _UnencryptedRoom(id: '!open:x', client: client);

      expect(
        liveLocationAvailability(open, sharingHere: false),
        LiveLocationAvailability.unavailable,
      );
    });
  });
}

class _UnencryptedRoom extends LiveLocationTestRoom {
  _UnencryptedRoom({required super.id, required super.client});

  @override
  bool get encrypted => false;
}
