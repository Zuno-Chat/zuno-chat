import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/read_model/nse_channel.dart';
import 'package:zuno/core/push/read_model/read_model_publisher.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

const _meta = (
  user: '@me:zuno.im',
  device: 'PHONE',
  serverOffsetMs: 1000,
  ringtone: false,
  voipCurrent: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> written;
  late Client client;

  Room joinedRoom(String id, {String? name}) {
    final room = Room(id: id, client: client, membership: Membership.join);
    if (name != null) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: '@me:zuno.im',
          stateKey: '',
          content: {'name': name},
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  Room directChat(String id, {required String partner, required String name}) {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        partner: [id],
      },
    );
    final room = joinedRoom(id);
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        senderId: partner,
        stateKey: partner,
        content: {'membership': 'join', 'displayname': name},
      ),
    );
    return room;
  }

  List<String> methods() => [for (final call in written) call.method];

  setUp(() {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    SharedPreferences.setMockInitialValues({});
    written = [];
    messenger.setMockMethodCallHandler(nseChannel, (call) async {
      written.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nseChannel, null));
    client = buildTestClient(userId: '@me:zuno.im', deviceId: 'PHONE');
  });

  test('meta carries the phase-two fields in contract order', () {
    expect(
      metaJson(_meta, heartbeatMs: 1790000000000),
      '{"v":1,"user":"@me:zuno.im","device":"PHONE","server_offset_ms":1000,'
      '"ringtone":false,"voip_current":true,"heartbeat_ms":1790000000000}',
    );
  });

  test('meta without a known server offset says so', () {
    final json = metaJson((
      user: '@me:zuno.im',
      device: 'PHONE',
      serverOffsetMs: null,
      ringtone: true,
      voipCurrent: false,
    ), heartbeatMs: 1);

    expect(jsonDecode(json), containsPair('server_offset_ms', null));
  });

  test('a chat publishes its partner, a room its title', () {
    final chat = directChat(
      '!dm:zuno.im',
      partner: '@alice:zuno.im',
      name: 'Alice',
    );
    final group = joinedRoom('!g:zuno.im', name: 'Design team');

    expect(jsonDecode(roomJson(chat)), {
      'v': 1,
      'room': '!dm:zuno.im',
      'title': 'Alice',
      'dm': true,
      'partner': 'Alice',
    });
    expect(jsonDecode(roomJson(group)), {
      'v': 1,
      'room': '!g:zuno.im',
      'title': 'Design team',
      'dm': false,
      'partner': '',
    });
  });

  test('a new session wipes what an earlier one left, then publishes meta '
      'and every joined room', () async {
    joinedRoom('!a:zuno.im', name: 'A');
    joinedRoom('!b:zuno.im', name: 'B');
    client.rooms.add(
      Room(id: '!left:zuno.im', client: client, membership: Membership.leave),
    );

    await ReadModelPublisher(now: () => DateTime.fromMillisecondsSinceEpoch(7))
        .start(client, _meta);

    expect(methods(), ['wipe', 'writeMeta', 'writeRoom', 'writeRoom']);
    expect(
      [for (final c in written.skip(2)) (c.arguments as Map)['room_id']],
      ['!a:zuno.im', '!b:zuno.im'],
    );
  });

  test('the same session starting again does not wipe', () async {
    final publisher = ReadModelPublisher();
    await publisher.start(client, _meta);
    written.clear();

    await ReadModelPublisher().start(client, _meta);

    expect(methods(), ['writeMeta']);
  });

  test('changed rooms are written once, a second after the last change', () {
    fakeAsync((time) {
      final publisher = ReadModelPublisher();
      unawaited(publisher.start(client, _meta));
      time.flushMicrotasks();
      written.clear();
      final room = joinedRoom('!a:zuno.im', name: 'Before');

      publisher.roomsChanged(['!a:zuno.im']);
      time.elapse(const Duration(milliseconds: 600));
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: '@me:zuno.im',
          stateKey: '',
          content: {'name': 'After'},
        ),
      );
      publisher.roomsChanged(['!a:zuno.im']);
      time.elapse(const Duration(milliseconds: 600));
      expect(written, isEmpty);

      time.elapse(const Duration(milliseconds: 500));
      time.flushMicrotasks();

      expect(methods(), ['writeRoom']);
      expect(
        jsonDecode(
          (written.single.arguments as Map)['json'] as String,
        )['title'],
        'After',
      );
    });
  });

  test('a room whose file is already current is not written again', () async {
    final publisher = ReadModelPublisher();
    joinedRoom('!a:zuno.im', name: 'A');
    await publisher.start(client, _meta);
    written.clear();

    publisher.roomsChanged(['!a:zuno.im']);
    await publisher.flush();

    expect(written, isEmpty);
  });

  test('a room left since is deleted', () async {
    final publisher = ReadModelPublisher();
    await publisher.start(client, _meta);
    written.clear();

    publisher.roomsChanged(['!gone:zuno.im']);
    await publisher.flush();

    expect(methods(), ['deleteRoom']);
  });

  test('stopping drops what was waiting', () {
    fakeAsync((time) {
      final publisher = ReadModelPublisher();
      unawaited(publisher.start(client, _meta));
      time.flushMicrotasks();
      written.clear();
      joinedRoom('!a:zuno.im', name: 'A');

      publisher.roomsChanged(['!a:zuno.im']);
      publisher.stop();
      time.elapse(const Duration(seconds: 2));

      expect(written, isEmpty);
    });
  });

  test('with the flag off nothing is published', () async {
    ambientCapabilities = androidCapabilities;
    joinedRoom('!a:zuno.im', name: 'A');

    await ReadModelPublisher().start(client, _meta);

    expect(written, isEmpty);
  });
}
