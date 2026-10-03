import 'dart:async';
import 'dart:convert';

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

  Room joinedRoom(String id, {required String name}) {
    final room = Room(id: id, client: client, membership: Membership.join)
      ..setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          senderId: '@me:zuno.im',
          stateKey: '',
          content: {'name': name},
        ),
      );
    client.rooms.add(room);
    return room;
  }

  Map<String, Object?> json(MethodCall call) =>
      jsonDecode((call.arguments as Map)['json'] as String)
          as Map<String, Object?>;

  setUp(() {
    ambientCapabilities = capabilitiesLike(
      iosCapabilities,
      voipRing: true,
      nseNotifications: true,
    );
    SharedPreferences.setMockInitialValues({});
    written = [];
    messenger.setMockMethodCallHandler(nseChannel, (call) async {
      written.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nseChannel, null));
    client = buildTestClient(userId: '@me:zuno.im', deviceId: 'PHONE');
  });

  test('phase three fields join meta and rooms without replacing phase two '
      'ones', () async {
    joinedRoom('!a:zuno.im', name: 'Design team');
    final publisher = ReadModelPublisher()
      ..metaExtras = (() async => {'level': 'name', 'user': '@spoof:zuno.im'})
      ..roomExtras = ((room) async => {
        'notifiers': ['@admin:zuno.im'],
        'room': '!spoof:zuno.im',
      });

    await publisher.start(client, _meta);

    final meta = json(written.firstWhere((c) => c.method == 'writeMeta'));
    final room = json(written.firstWhere((c) => c.method == 'writeRoom'));
    expect(meta['level'], 'name');
    expect(meta['user'], '@me:zuno.im');
    expect(room['notifiers'], ['@admin:zuno.im']);
    expect(room['room'], '!a:zuno.im');
    expect(room['title'], 'Design team');
  });

  test('without titles a room file names nothing', () async {
    joinedRoom('!a:zuno.im', name: 'Design team');
    final publisher = ReadModelPublisher()..titles = false;

    await publisher.start(client, _meta);

    final room = json(written.firstWhere((c) => c.method == 'writeRoom'));
    expect(room['title'], '');
    expect(room['partner'], '');
  });

  test('a level change rewrites meta and every room that changed', () async {
    joinedRoom('!a:zuno.im', name: 'A');
    joinedRoom('!b:zuno.im', name: 'B');
    var level = 'full';
    final publisher = ReadModelPublisher()
      ..metaExtras = (() async => {'level': level});
    await publisher.start(client, _meta);
    written.clear();

    level = 'none';
    publisher.titles = false;
    await publisher.refreshMeta();
    await publisher.publishAll();
    final rewritten = written.length;
    await publisher.publishAll();

    expect(written.map((c) => c.method), [
      'writeMeta',
      'writeRoom',
      'writeRoom',
    ]);
    expect(json(written.first)['level'], 'none');
    expect(written.length, rewritten);
  });

  test('a forced pass rewrites rooms the extension lost', () async {
    joinedRoom('!a:zuno.im', name: 'A');
    final publisher = ReadModelPublisher();
    await publisher.start(client, _meta);
    written.clear();

    await publisher.publishAll();
    await publisher.publishAll(force: true);

    expect(written.map((c) => c.method), ['writeRoom']);
  });

  test('a room whose extras fail is skipped and written once they work, the '
      'others are not held up', () async {
    joinedRoom('!a:zuno.im', name: 'A');
    joinedRoom('!b:zuno.im', name: 'B');
    var failing = true;
    final publisher = ReadModelPublisher()
      ..roomExtras = ((room) async =>
          failing && room.id == '!a:zuno.im' ? throw StateError('extras') : {});

    await publisher.start(client, _meta);
    failing = false;
    await publisher.publishAll();

    expect(
      [
        for (final call in written)
          if (call.method == 'writeRoom') (call.arguments as Map)['room_id'],
      ],
      ['!b:zuno.im', '!a:zuno.im'],
    );
  });

  test(
    'extras withdrawn while a room is prepared leave no file behind',
    () async {
      joinedRoom('!a:zuno.im', name: 'A');
      final pending = Completer<Map<String, Object?>>();
      final publisher = ReadModelPublisher()
        ..holdUntilExtras = true
        ..titles = false
        ..metaExtras = (() async => {'level': 'none'})
        ..roomExtras = ((room) => pending.future);

      final starting = publisher.start(client, _meta);
      await pumpEventQueue();
      publisher
        ..metaExtras = null
        ..roomExtras = null
        ..titles = true;
      pending.complete({});
      await starting;

      expect(written.where((call) => call.method == 'writeRoom'), isEmpty);
    },
  );

  test(
    'a publisher stopped while a room is prepared leaves no file behind',
    () async {
      joinedRoom('!a:zuno.im', name: 'A');
      final pending = Completer<Map<String, Object?>>();
      final publisher = ReadModelPublisher()
        ..roomExtras = ((room) => pending.future);

      final starting = publisher.start(client, _meta);
      await pumpEventQueue();
      publisher.stop();
      pending.complete({});
      await starting;

      expect(written.where((call) => call.method == 'writeRoom'), isEmpty);
    },
  );

  test(
    'a publisher stopped while its meta is prepared leaves no meta behind',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final publisher = ReadModelPublisher()
        ..metaExtras = (() => pending.future);

      final starting = publisher.start(client, _meta);
      await pumpEventQueue();
      publisher.stop();
      pending.complete({'level': 'none'});
      await starting;

      expect(written.where((call) => call.method == 'writeMeta'), isEmpty);
    },
  );

  test(
    'extras withdrawn while meta is prepared leave no meta behind',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final publisher = ReadModelPublisher()
        ..holdUntilExtras = true
        ..metaExtras = (() => pending.future);

      final starting = publisher.start(client, _meta);
      await pumpEventQueue();
      publisher
        ..metaExtras = null
        ..roomExtras = null;
      pending.complete({'level': 'none'});
      await starting;

      expect(written.where((call) => call.method == 'writeMeta'), isEmpty);
    },
  );

  test(
    'a publisher stopped while its session is wiped does no more work',
    () async {
      joinedRoom('!a:zuno.im', name: 'A');
      final wiping = Completer<void>();
      messenger.setMockMethodCallHandler(nseChannel, (call) async {
        written.add(call);
        if (call.method == 'wipe') await wiping.future;
        return null;
      });
      var prepared = 0;
      final publisher = ReadModelPublisher()
        ..metaExtras = (() async {
          prepared++;
          return {};
        })
        ..roomExtras = ((room) async {
          prepared++;
          return {};
        });

      final starting = publisher.start(client, _meta);
      await pumpEventQueue();
      publisher.stop();
      wiping.complete();
      await starting;

      expect(prepared, 0);
      expect([for (final call in written) call.method], ['wipe']);
    },
  );

  test('before start nothing is refreshed or published', () async {
    joinedRoom('!a:zuno.im', name: 'A');
    final publisher = ReadModelPublisher();

    await publisher.refreshMeta();
    await publisher.publishAll();

    expect(written, isEmpty);
  });
}
