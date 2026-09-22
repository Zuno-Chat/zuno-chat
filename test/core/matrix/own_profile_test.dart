import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/own_profile.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late int requests;

  setUp(() {
    requests = 0;
    client = buildTestClient(
      userId: '@alex:example.org',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
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
