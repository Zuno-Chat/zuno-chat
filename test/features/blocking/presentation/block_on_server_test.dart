import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/blocking/presentation/block_person.dart';

import '../../../helpers/fake_matrix.dart';

class _ClearableDatabase extends FakeDatabaseApi {
  int cacheClears = 0;

  @override
  Future<void> clearCache() async => cacheClears++;
}

void main() {
  late List<http.Request> requests;
  late _ClearableDatabase database;
  late Client client;
  var refuseAccountData = false;

  setUp(() {
    requests = [];
    refuseAccountData = false;
    database = _ClearableDatabase();
    client = buildTestClient(
      userId: '@me:example.org',
      database: database,
      httpClient: MockClient((request) {
        if (request.url.path.endsWith('/sync')) {
          return Completer<http.Response>().future;
        }
        requests.add(request);
        if (refuseAccountData && request.url.path.contains('/account_data/')) {
          return Future.value(
            http.Response(jsonEncode({'errcode': 'M_UNKNOWN'}), 500),
          );
        }
        return Future.value(http.Response('{}', 200));
      }),
    )..homeserver = Uri.parse('https://example.org');
    client.bearerToken = 'token';
    addTearDown(client.abortSync);
  });

  Room addRoom(String id, Membership membership) {
    final room = buildTestRoom(client, id: id)..membership = membership;
    client.rooms.add(room);
    return room;
  }

  void inviteFrom(Room room, String sender) => room.setState(
    buildTestEvent(
      room,
      eventId: '\$invite-${room.id}',
      senderId: sender,
      type: EventTypes.RoomMember,
      stateKey: '@me:example.org',
      content: {'membership': 'invite'},
    ),
  );

  Iterable<String> leftRooms() => requests
      .where((r) => r.url.path.endsWith('/leave'))
      .map((r) => Uri.decodeComponent(r.url.pathSegments[4]));

  test('stores the person in the blocked list on the server', () async {
    await blockOnServer(client, '@ann:example.org');

    final stored = requests.singleWhere(
      (r) => r.url.path.endsWith('/account_data/m.ignored_user_list'),
    );
    expect(stored.method, 'PUT');
    expect(jsonDecode(stored.body), {
      'ignored_users': {'@ann:example.org': <String, Object?>{}},
    });
  });

  test('keeps the people who were already blocked', () async {
    client.accountData['m.ignored_user_list'] = BasicEvent(
      type: 'm.ignored_user_list',
      content: {
        'ignored_users': {'@ben:example.org': <String, Object?>{}},
      },
    );

    await blockOnServer(client, '@ann:example.org');

    final stored = requests.singleWhere(
      (r) => r.url.path.endsWith('/account_data/m.ignored_user_list'),
    );
    expect(
      (jsonDecode(stored.body)['ignored_users'] as Map).keys,
      unorderedEquals(['@ben:example.org', '@ann:example.org']),
    );
  });

  test('leaves the chat with them and declines their invitation, '
      'and nothing else', () async {
    addRoom('!chat:example.org', Membership.join);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@ann:example.org': ['!chat:example.org'],
      },
    );
    inviteFrom(
      addRoom('!invite:example.org', Membership.invite),
      '@ann:example.org',
    );
    inviteFrom(
      addRoom('!other:example.org', Membership.invite),
      '@ben:example.org',
    );
    addRoom('!shared:example.org', Membership.join);

    await blockOnServer(client, '@ann:example.org');

    expect(
      leftRooms(),
      unorderedEquals(['!chat:example.org', '!invite:example.org']),
    );
  });

  test('clears the saved messages so their old ones go too', () async {
    await blockOnServer(client, '@ann:example.org');

    expect(database.cacheClears, 1);
  });

  test('a refusal from the server surfaces, and clears nothing', () async {
    refuseAccountData = true;

    await expectLater(
      blockOnServer(client, '@ann:example.org'),
      throwsA(isA<MatrixException>()),
    );
    expect(database.cacheClears, 0);
  });

  test('refuses something that is not a username', () async {
    await expectLater(blockOnServer(client, 'ann'), throwsException);
    expect(requests, isEmpty);
  });
}
