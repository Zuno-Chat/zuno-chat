import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/own_profile.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late int requests;
  late List<http.Request> sent;
  late int status;

  setUp(() {
    requests = 0;
    sent = [];
    status = 200;
    client = buildTestClient(
      userId: '@alex:example.org',
      httpClient: FakeHttpClient((request) async {
        requests++;
        sent.add(request);
        return http.Response(
          status == 200 ? '{}' : '{"errcode": "M_FORBIDDEN", "error": "No"}',
          status,
        );
      }),
    );
  });

  group('setOwnDisplayName', () {
    setUp(() {
      client
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'token';
    });

    test('saves the name as your display name', () async {
      await setOwnDisplayName(client, 'Alex');

      final request = sent.single;
      expect(request.method, 'PUT');
      expect(
        request.url.path,
        endsWith(
          '/profile/${Uri.encodeComponent('@alex:example.org')}/displayname',
        ),
      );
      expect(jsonDecode(request.body), {'displayname': 'Alex'});
    });

    test('passes a server refusal on', () async {
      status = 403;

      await expectLater(
        setOwnDisplayName(client, 'Alex'),
        throwsA(isA<MatrixException>()),
      );
    });
  });

  test('reads the name and photo from a joined room, with no request', () {
    final room = buildTestRoom(client)..partial = false;
    room.setState(
      User(
        '@alex:example.org',
        membership: 'join',
        displayName: 'Alex',
        avatarUrl: 'mxc://example.org/me',
        room: room,
      ),
    );
    client.rooms.add(room);

    final profile = ownProfileFromMemory(client);

    expect(profile.name, 'Alex');
    expect(profile.avatar, Uri.parse('mxc://example.org/me'));
    expect(requests, 0);
  });

  test('skips rooms that are only invitations', () {
    final invite = buildTestRoom(client, id: '!invite:example.org')
      ..membership = Membership.invite;
    invite.setState(
      User(
        '@alex:example.org',
        membership: 'invite',
        displayName: 'Wrong',
        room: invite,
      ),
    );
    client.rooms.add(invite);

    expect(ownProfileFromMemory(client).name, 'alex');
  });

  test('falls back to the username when there is no room yet', () {
    final profile = ownProfileFromMemory(client);
    expect(profile.name, 'alex');
    expect(profile.avatar, isNull);
    expect(requests, 0);
  });

  test('a joined room without your member event asks nobody', () async {
    final room = buildTestRoom(client)..partial = false;
    client.rooms.add(room);

    expect(ownProfileFromMemory(client).name, 'alex');
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
  });
}
