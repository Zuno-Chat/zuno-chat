import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/join_room.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late List<http.Request> requests;

  setUp(() {
    requests = [];
    client = buildTestClient(
      userId: '@me:example.org',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/join/')) {
          return http.Response(
            jsonEncode({'room_id': '!garden:example.org'}),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
  });

  test('asks the server to join through the given servers', () async {
    client.rooms.add(
      buildTestRoom(client, id: '!garden:example.org')
        ..membership = Membership.join,
    );

    await joinAndAwaitRoom(client, '!garden:example.org', via: ['zuno.chat']);

    final join = requests.single;
    expect(
      Uri.decodeComponent(join.url.path),
      '/_matrix/client/v3/join/!garden:example.org',
    );
    expect(join.url.queryParametersAll['via'], ['zuno.chat']);
  });

  test('a room the sync already brought is returned at once', () async {
    final garden = buildTestRoom(client, id: '!garden:example.org')
      ..membership = Membership.join;
    client.rooms.add(garden);

    expect(await joinAndAwaitRoom(client, garden.id), garden);
  });

  test('otherwise waits for the sync that brings the room', () async {
    final joined = joinAndAwaitRoom(client, '!garden:example.org');
    var done = false;
    joined.whenComplete(() => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);

    final garden = buildTestRoom(client, id: '!garden:example.org')
      ..membership = Membership.join;
    client.rooms.add(garden);
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'next',
        rooms: RoomsUpdate(join: {garden.id: JoinedRoomUpdate()}),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));

    expect(await joined, garden);
  });

  test('a refused join throws and waits for nothing', () async {
    client = buildTestClient(
      userId: '@me:example.org',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
          403,
        ),
      ),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';

    await expectLater(
      joinAndAwaitRoom(client, '!garden:example.org'),
      throwsA(isA<MatrixException>()),
    );
  });
}
