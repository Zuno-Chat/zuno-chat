import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/ring_identity.dart';
import 'package:zuno/core/l10n/l10n.dart';

import '../../helpers/fake_matrix.dart';

class _ProfilesDatabaseApi extends FakeDatabaseApi {
  final Map<String, User> users = {};
  final profileLookups = <String>[];
  bool fails = false;

  @override
  Future<User?> getUser(String userId, Room room) async {
    if (fails) throw StateError('database closed');
    return users[userId];
  }

  @override
  Future<CachedProfileInformation?> getUserProfile(String userId) async {
    profileLookups.add(userId);
    return null;
  }
}

void main() {
  late _ProfilesDatabaseApi db;
  late Client client;
  late Room room;
  late List<String> requests;

  setUp(() {
    db = _ProfilesDatabaseApi();
    requests = [];
    client = buildTestClient(
      userId: '@me:example.org',
      database: db,
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        return http.Response('{}', 404);
      }),
    )..homeserver = Uri.parse('https://example.org');
    room = buildTestRoom(client);
  });

  IncomingCall call() => IncomingCall(
    room: room,
    callId: 'call1',
    callerId: '@bob:example.org',
    kind: CallKind.voice,
  );

  void setState(String type, Map<String, Object?> content, {String? key}) =>
      room.setState(
        buildTestEvent(
          room,
          eventId: '\$$type-$key',
          senderId: '@bob:example.org',
          type: type,
          stateKey: key ?? '',
          content: content,
        ),
      );

  void addCaller() => setState(EventTypes.RoomMember, {
    'membership': 'join',
    'displayname': 'Bob Jones',
    'avatar_url': 'mxc://example.org/bob',
  }, key: '@bob:example.org');

  void markDirect() => client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: {
      '@bob:example.org': [room.id],
    },
  );

  group('a group call', () {
    test('rings under the group\'s name and picture, never the '
        'caller\'s', () {
      addCaller();
      setState(EventTypes.RoomName, {'name': 'Weekend hike'});
      setState(EventTypes.RoomAvatar, {'url': 'mxc://example.org/hike'});

      final ring = ringIdentity(call(), englishLocalizations);

      expect(ring.name, 'Weekend hike');
      expect(ring.avatarUrl, Uri.parse('mxc://example.org/hike'));
      expect(ring.toneSeed, room.id);
    });

    test('names the caller under the group when the room knows them', () {
      addCaller();
      setState(EventTypes.RoomName, {'name': 'Weekend hike'});

      expect(ringIdentity(call(), englishLocalizations).caller, 'Bob Jones');
    });

    test('names a caller kept on this device once loaded', () async {
      setState(EventTypes.RoomName, {'name': 'Weekend hike'});
      db.users['@bob:example.org'] = User(
        '@bob:example.org',
        displayName: 'Bob Stored',
        room: room,
      );

      await loadRingIdentity(call(), allowNetwork: true);

      expect(ringIdentity(call(), englishLocalizations).caller, 'Bob Stored');
      expect(requests, isEmpty);
    });

    test('names no caller it does not already know, and asks the server '
        'nothing to find one', () async {
      setState(EventTypes.RoomName, {'name': 'Weekend hike'});

      await loadRingIdentity(call(), allowNetwork: true);
      final ring = ringIdentity(call(), englishLocalizations);
      await pumpEventQueue();

      expect(ring.caller, isNull);
      expect(requests, isEmpty);
      expect(db.profileLookups, isEmpty);
    });

    test('of a group with no name or members rings as an empty chat', () {
      final ring = ringIdentity(call(), englishLocalizations);

      expect(ring.name, 'Empty chat');
      expect(ring.avatarUrl, isNull);
    });

    test('of a group named after its members loads them first', () async {
      room.summary.mHeroes = ['@carol:example.org'];
      db.users['@carol:example.org'] = User(
        '@carol:example.org',
        displayName: 'Carol Stored',
        room: room,
      );

      expect(
        ringIdentity(call(), englishLocalizations).name,
        isNot(contains('Carol Stored')),
      );

      await loadRingIdentity(call());

      expect(
        ringIdentity(call(), englishLocalizations).name,
        'Group with Carol Stored',
      );
    });
  });

  group('a one-to-one call', () {
    test('rings under the caller\'s name and picture', () {
      markDirect();
      addCaller();

      final ring = ringIdentity(call(), englishLocalizations);

      expect(ring.name, 'Bob Jones');
      expect(ring.caller, isNull);
      expect(ring.avatarUrl, Uri.parse('mxc://example.org/bob'));
      expect(ring.toneSeed, '@bob:example.org');
    });

    test('from a caller the room has never heard of rings under the name '
        'in their user id', () {
      markDirect();

      expect(ringIdentity(call(), englishLocalizations).name, 'Bob');
    });

    test('rings under the caller once they are loaded', () async {
      markDirect();
      db.users['@bob:example.org'] = User(
        '@bob:example.org',
        displayName: 'Bob Stored',
        room: room,
      );

      await loadRingIdentity(call());

      expect(ringIdentity(call(), englishLocalizations).name, 'Bob Stored');
    });

    test('still rings, under the name in the caller\'s user id, when this '
        'device cannot load them', () async {
      markDirect();
      db.fails = true;

      await loadRingIdentity(call());

      expect(ringIdentity(call(), englishLocalizations).name, 'Bob');
    });
  });
}
