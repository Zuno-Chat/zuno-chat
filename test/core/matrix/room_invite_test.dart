import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_invite.dart';

import '../../helpers/fake_matrix.dart';

class _MemberDatabase extends FakeDatabaseApi {
  final Map<String, User Function(Room)> members;

  _MemberDatabase(this.members);

  @override
  Future<User?> getUser(String userId, Room room) async =>
      members[userId]?.call(room);

  @override
  Future<void> forgetRoom(String roomId) async {}
}

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.membership = Membership.join;
  });

  void setMember(
    String userId, {
    required String membership,
    String? displayName,
    String? avatarUrl,
    String senderId = '@me:example.org',
  }) {
    room.setState(
      Event(
        eventId: '\$member-$userId-$membership',
        type: EventTypes.RoomMember,
        stateKey: userId,
        senderId: senderId,
        originServerTs: DateTime.now(),
        content: {
          'membership': membership,
          'displayname': ?displayName,
          'avatar_url': ?avatarUrl,
        },
        room: room,
      ),
    );
  }

  void setRoomName(String name) {
    room.setState(
      Event(
        eventId: r'$name',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: '@me:example.org',
        originServerTs: DateTime.now(),
        content: {'name': name},
        room: room,
      ),
    );
  }

  group('a chat this user started, still unanswered', () {
    setUp(() {
      setMember('@me:example.org', membership: 'join');
      setMember(
        '@bob:example.org',
        membership: 'invite',
        displayName: 'Bob Bobson',
        avatarUrl: 'mxc://example.org/bob',
      );
    });

    test('is awaiting acceptance', () {
      expect(isAwaitingInviteAcceptance(room), isTrue);
      expect(pendingInvitees(room).single.id, '@bob:example.org');
    });

    test('shows the Matrix ID, never the invitee\'s profile', () {
      final display = roomInviteDisplay(room);

      expect(display.awaitingAcceptance, isTrue);
      expect(display.title, '@bob');
      expect(display.title, isNot(contains('Bobson')));
      expect(display.avatarUrl, isNull);
    });

    test('names who is being waited on', () {
      expect(pendingInviteSubtitle(room), 'Waiting for @bob to accept');
    });

    test('keeps a named group\'s own name and avatar', () {
      setRoomName('Weekend plans');

      final display = roomInviteDisplay(room);

      expect(display.awaitingAcceptance, isTrue);
      expect(display.title, 'Weekend plans');
    });
  });

  test('stops being pending once the invitee joins', () {
    setMember('@me:example.org', membership: 'join');
    setMember('@bob:example.org', membership: 'join', displayName: 'Bob');

    expect(isAwaitingInviteAcceptance(room), isFalse);
    final display = roomInviteDisplay(room);
    expect(display.awaitingAcceptance, isFalse);
    expect(display.title, room.getLocalizedDisplayname());
    expect(display.avatarUrl, room.avatar);
  });

  test('a group where one of two invitees joined is not pending', () {
    setMember('@me:example.org', membership: 'join');
    setMember('@bob:example.org', membership: 'join', displayName: 'Bob');
    setMember('@carol:example.org', membership: 'invite');

    expect(isAwaitingInviteAcceptance(room), isFalse);
  });

  test('an ordinary chat with nobody invited is not pending', () {
    setMember('@me:example.org', membership: 'join');

    expect(isAwaitingInviteAcceptance(room), isFalse);
    expect(pendingInvitees(room), isEmpty);
  });

  group('an invitation waiting on this user', () {
    setUp(() {
      room.membership = Membership.invite;
      setMember(
        '@me:example.org',
        membership: 'invite',
        senderId: '@alice:example.org',
      );
      setMember(
        '@alice:example.org',
        membership: 'join',
        displayName: 'Alice',
        senderId: '@alice:example.org',
      );
    });

    test('is an incoming invite, not an outgoing one', () {
      expect(isIncomingInvite(room), isTrue);
      expect(isAwaitingInviteAcceptance(room), isFalse);
    });

    test('knows who sent it', () {
      expect(inviterId(room), '@alice:example.org');
    });

    test('nothing is withheld from the person deciding', () {
      final display = roomInviteDisplay(room);

      expect(display.awaitingAcceptance, isFalse);
      expect(display.title, room.getLocalizedDisplayname());
      expect(display.avatarUrl, room.avatar);
    });
  });

  group('restored from disk, with no member state loaded', () {
    setUp(() {
      room.membership = Membership.invite;
      room.summary = RoomSummary.fromJson({
        'm.heroes': ['@alice:example.org'],
        'm.joined_member_count': 1,
        'm.invited_member_count': 1,
      });
    });

    test('still knows who invited us, from the summary heroes', () {
      expect(inviterId(room), '@alice:example.org');
    });

    test('reads a profile-substituted member event as not loaded', () {
      room.setState(User('@me:example.org', membership: 'invite', room: room));

      expect(ownInviteMember(room), isNull);
      expect(isDirectInvite(room), isFalse);
      expect(inviterId(room), '@alice:example.org');
    });

    test(
      'loadInviteMembers restores the invitation from the database',
      () async {
        client.database = _MemberDatabase({
          '@me:example.org': (r) => User.fromState(
            stateKey: '@me:example.org',
            senderId: '@alice:example.org',
            typeKey: EventTypes.RoomMember,
            content: {'membership': 'invite', 'is_direct': true},
            room: r,
          ),
          '@alice:example.org': (r) =>
              User('@alice:example.org', displayName: 'Alice', room: r),
        });

        await loadInviteMembers(room);

        expect(ownInviteMember(room)?.senderId, '@alice:example.org');
        expect(isDirectInvite(room), isTrue);
        expect(
          room
              .unsafeGetUserFromMemoryOrFallback('@alice:example.org')
              .displayName,
          'Alice',
        );
      },
    );

    test('loadInviteMembers survives a database that has nothing', () async {
      client.database = _MemberDatabase({});

      await loadInviteMembers(room);

      expect(ownInviteMember(room), isNull);
      expect(isDirectInvite(room), isFalse);
    });
  });

  group("the sender's pending indicator, restored from disk", () {
    setUp(() {
      room.membership = Membership.join;
      room.summary = RoomSummary.fromJson({
        'm.heroes': ['@bob:example.org'],
        'm.joined_member_count': 1,
        'm.invited_member_count': 1,
      });
    });

    test('is still pending with no member state at all', () {
      expect(isAwaitingInviteAcceptance(room), isTrue);
      expect(pendingInviteeIds(room), ['@bob:example.org']);
      expect(roomInviteDisplay(room).title, '@bob');
      expect(roomInviteDisplay(room).avatarUrl, isNull);
      expect(pendingInviteSubtitle(room), 'Waiting for @bob to accept');
    });

    test('stops being pending once the summary shows two joined', () {
      room.summary = RoomSummary.fromJson({
        'm.heroes': ['@bob:example.org'],
        'm.joined_member_count': 2,
        'm.invited_member_count': 0,
      });

      expect(isAwaitingInviteAcceptance(room), isFalse);
    });
  });

  group('declining an invitation', () {
    late List<String> requests;

    Client declineClient({int forgetStatus = 200}) {
      requests = [];
      final httpClient = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/forget')) {
          return http.Response(
            forgetStatus == 200
                ? '{}'
                : jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
            forgetStatus,
          );
        }
        return http.Response('{}', 200);
      });
      return Client(
          'test',
          database: _MemberDatabase({}),
          httpClient: httpClient,
        )
        ..setUserId('@me:example.org')
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'test-token';
    }

    Room invitedRoom(Client client, {required bool isDirect}) {
      final room = buildTestRoom(client)..membership = Membership.invite;
      room.setState(
        Event(
          eventId: r'$invite',
          type: EventTypes.RoomMember,
          stateKey: '@me:example.org',
          senderId: '@bob:example.org',
          originServerTs: DateTime.now(),
          content: {'membership': 'invite', if (isDirect) 'is_direct': true},
          room: room,
        ),
      );
      return room;
    }

    test('a declined direct chat is left and then forgotten', () async {
      final client = declineClient();

      await declineInvite(invitedRoom(client, isDirect: true));

      expect(requests.where((r) => r.endsWith('/leave')), hasLength(1));
      expect(requests.where((r) => r.endsWith('/forget')), hasLength(1));
      expect(
        requests.indexWhere((r) => r.endsWith('/leave')),
        lessThan(requests.indexWhere((r) => r.endsWith('/forget'))),
      );
    });

    test('a declined group invitation is left but kept', () async {
      final client = declineClient();

      await declineInvite(invitedRoom(client, isDirect: false));

      expect(requests.where((r) => r.endsWith('/leave')), hasLength(1));
      expect(requests.where((r) => r.endsWith('/forget')), isEmpty);
    });

    test(
      'a homeserver that refuses to forget still declines cleanly',
      () async {
        final client = declineClient(forgetStatus: 403);

        await expectLater(
          declineInvite(invitedRoom(client, isDirect: true)),
          completes,
        );
        expect(requests.where((r) => r.endsWith('/leave')), hasLength(1));
      },
    );

    test('a restored invitation is still recognised as direct', () async {
      requests = [];
      final httpClient = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response('{}', 200);
      });
      late Room room;
      final client =
          Client(
              'test',
              database: _MemberDatabase({
                '@me:example.org': (r) => User.fromState(
                  stateKey: '@me:example.org',
                  senderId: '@bob:example.org',
                  typeKey: EventTypes.RoomMember,
                  content: const {'membership': 'invite', 'is_direct': true},
                  room: r,
                ),
              }),
              httpClient: httpClient,
            )
            ..setUserId('@me:example.org')
            ..homeserver = Uri.parse('https://example.org')
            ..accessToken = 'test-token';
      room = buildTestRoom(client)..membership = Membership.invite;

      await declineInvite(room);

      expect(requests.where((r) => r.endsWith('/forget')), hasLength(1));
    });
  });
}
