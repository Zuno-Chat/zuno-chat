import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/join_requests.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/preferences_container.dart';

const _me = '@me:example.org';
const _asked = '!coaches:example.org';

void main() {
  late Client client;
  late List<http.Request> requests;
  late bool refuse;

  Iterable<String> paths() =>
      requests.map((r) => Uri.decodeComponent(r.url.path));

  setUp(() {
    requests = [];
    refuse = false;
    client = buildTestClient(
      userId: _me,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (refuse) {
          return http.Response(
            jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
            403,
          );
        }
        final path = Uri.decodeComponent(request.url.path);
        if (path.contains('/knock/') || path.endsWith('/join')) {
          return http.Response(jsonEncode({'room_id': _asked}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
  });

  Future<ProviderContainer> container({List<String>? stored}) =>
      containerWithPreferences(
        {'communities.asked.$_me': ?stored},
        overrides: [matrixClientProvider.overrideWithValue(client)],
      );

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Room invitedTo(String id) {
    final room = buildTestRoom(client, id: id)..membership = Membership.invite;
    client.rooms.add(room);
    return room;
  }

  void sync({Map<String, LeftRoomUpdate>? leave}) => client.onSync.add(
    SyncUpdate(
      nextBatch: 'next',
      rooms: RoomsUpdate(leave: leave),
    ),
  );

  group('asking', () {
    test('knocks through the given servers and remembers the room', () async {
      final c = await container();

      await c
          .read(joinRequestsProvider.notifier)
          .ask(_asked, via: ['example.org']);

      final knock = requests.single;
      expect(
        Uri.decodeComponent(knock.url.path),
        '/_matrix/client/v3/knock/$_asked',
      );
      expect(knock.url.queryParametersAll['via'], ['example.org']);
      expect(c.read(joinRequestsProvider), {_asked});
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getStringList('communities.asked.$_me'), [_asked]);
    });

    test('a refused request is not remembered', () async {
      final c = await container();
      refuse = true;

      await expectLater(
        c.read(joinRequestsProvider.notifier).ask(_asked),
        throwsA(isA<MatrixException>()),
      );
      expect(c.read(joinRequestsProvider), isEmpty);
    });

    test('a request survives a restart', () async {
      final c = await container(stored: [_asked]);

      expect(c.read(joinRequestsProvider), {_asked});
    });

    test('withdrawing leaves the room and forgets the request', () async {
      final c = await container(stored: [_asked]);

      await c.read(joinRequestsProvider.notifier).withdraw(_asked);

      expect(paths(), ['/_matrix/client/v3/rooms/$_asked/leave']);
      expect(c.read(joinRequestsProvider), isEmpty);
    });
  });

  group('the answer', () {
    test('an approval is joined at once and the request forgotten', () async {
      final c = await container(stored: [_asked]);
      c.read(joinRequestsProvider);
      final room = invitedTo(_asked);
      client.onSyncStatus.stream.listen((_) {});

      sync();
      await settle();
      room.membership = Membership.join;
      sync();
      await settle();

      expect(paths(), contains('/_matrix/client/v3/rooms/$_asked/join'));
      expect(c.read(joinRequestsProvider), isEmpty);
    });

    test('an approval that arrived while Zuno was closed is joined on '
        'start', () async {
      invitedTo(_asked);
      final c = await container(stored: [_asked]);

      c.read(joinRequestsProvider);
      await settle();

      expect(paths(), contains('/_matrix/client/v3/rooms/$_asked/join'));
    });

    test('a join that fails forgets the request, so the approval shows as '
        'a normal invitation', () async {
      invitedTo(_asked);
      refuse = true;
      final c = await container(stored: [_asked]);

      c.read(joinRequestsProvider);
      await settle();

      expect(c.read(joinRequestsProvider), isEmpty);
    });

    test('a declined request is forgotten', () async {
      final c = await container(stored: [_asked]);
      c.read(joinRequestsProvider);

      sync(leave: {_asked: LeftRoomUpdate()});
      await settle();

      expect(c.read(joinRequestsProvider), isEmpty);
      expect(requests, isEmpty);
    });

    test('other syncs leave the request waiting', () async {
      final c = await container(stored: [_asked]);
      c.read(joinRequestsProvider);

      sync();
      await settle();

      expect(c.read(joinRequestsProvider), {_asked});
      expect(requests, isEmpty);
    });
  });

  test('another account signing in reads its own requests', () async {
    final c = await container(stored: [_asked]);
    expect(c.read(joinRequestsProvider), {_asked});

    client.setUserId('@other:example.org');
    client.onLoginStateChanged.add(LoginState.loggedIn);
    await settle();

    expect(c.read(joinRequestsProvider), isEmpty);
  });

  group('answering', () {
    late Room room;

    void member(String userId, String membership, {String? name}) =>
        room.setState(
          User(userId, membership: membership, displayName: name, room: room),
        );

    void levels(int mine) => room.setState(
      Event(
        eventId: r'$levels',
        type: EventTypes.RoomPowerLevels,
        stateKey: '',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2026),
        content: {
          'users': {_me: mine},
          'invite': 0,
          'kick': 50,
        },
        room: room,
      ),
    );

    setUp(() {
      room = buildTestRoom(client, id: '!beginners:example.org')
        ..membership = Membership.join;
      client.rooms.add(room);
      member(_me, 'join');
      member('@maya:example.org', 'knock', name: 'Maya');
      member('@leo:example.org', 'join', name: 'Leo');
    });

    test('lists the people asking, not the people already in', () {
      expect(pendingJoinRequests(room).map((u) => u.id), ['@maya:example.org']);
    });

    test('moderators and admins answer; members do not', () {
      levels(50);
      expect(canAnswerJoinRequests(room), isTrue);

      levels(0);
      expect(canAnswerJoinRequests(room), isFalse);
    });

    test(
      'letting someone in invites them and clears the request at once',
      () async {
        levels(100);

        await letIn(room, '@maya:example.org');

        final invite = requests.single;
        expect(invite.url.path, endsWith('/invite'));
        expect(jsonDecode(invite.body), {'user_id': '@maya:example.org'});
        expect(pendingJoinRequests(room), isEmpty);
      },
    );

    test('declining removes the request at once', () async {
      levels(100);

      await declineJoinRequest(room, '@maya:example.org');

      final kick = requests.single;
      expect(kick.url.path, endsWith('/kick'));
      expect(jsonDecode(kick.body)['user_id'], '@maya:example.org');
      expect(pendingJoinRequests(room), isEmpty);
    });

    test('a refused answer leaves the request as it was', () async {
      levels(100);
      refuse = true;

      await expectLater(
        letIn(room, '@maya:example.org'),
        throwsA(isA<MatrixException>()),
      );
      expect(pendingJoinRequests(room).map((u) => u.id), ['@maya:example.org']);
    });
  });
}
