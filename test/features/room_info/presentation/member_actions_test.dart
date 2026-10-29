import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/official_room.dart';
import 'package:zuno/features/room_info/presentation/member_actions.dart';
import 'package:zuno/features/room_info/presentation/remove_member_dialog.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Room roomAs(String me, Map<String, int> users, {bool community = false}) {
    final room = buildTestRoom(buildTestClient(userId: me))
      ..membership = Membership.join;
    if (community) {
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$create',
          senderId: '@creator:example.org',
          type: EventTypes.RoomCreate,
          stateKey: '',
          content: {'type': RoomCreationTypes.mSpace},
        ),
      );
    }
    setPowerLevels(room, {'users': users});
    return room;
  }

  User member(Room room, String id, {String membership = 'join'}) =>
      User(id, membership: membership, room: room);

  group('memberActionsFor', () {
    test('an admin can do everything to a member of a room', () {
      final room = roomAs('@admin:example.org', {'@admin:example.org': 100});

      expect(memberActionsFor(room, member(room, '@bob:example.org')), [
        MemberAction.message,
        MemberAction.changeRole,
        MemberAction.remove,
        MemberAction.ban,
        MemberAction.block,
        MemberAction.report,
      ]);
    });

    test('a member of a room can still message, block and report', () {
      final room = roomAs('@me:example.org', {});

      expect(memberActionsFor(room, member(room, '@bob:example.org')), [
        MemberAction.message,
        MemberAction.block,
        MemberAction.report,
      ]);
    });

    test('a community offers only moderation', () {
      final room = roomAs('@admin:example.org', {
        '@admin:example.org': 100,
      }, community: true);

      expect(memberActionsFor(room, member(room, '@bob:example.org')), [
        MemberAction.changeRole,
        MemberAction.remove,
        MemberAction.ban,
      ]);
      final plain = roomAs('@me:example.org', {}, community: true);
      expect(memberActionsFor(plain, member(plain, '@bob:example.org')), []);
    });

    test('nothing for yourself, an invitee or in a direct chat', () {
      final room = roomAs('@admin:example.org', {'@admin:example.org': 100});

      expect(memberActionsFor(room, member(room, '@admin:example.org')), []);
      expect(
        memberActionsFor(
          room,
          member(room, '@bob:example.org', membership: 'invite'),
        ),
        [],
      );

      room.client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@bob:example.org': [room.id],
        },
      );
      expect(memberActionsFor(room, member(room, '@bob:example.org')), []);
    });

    test('nobody blocks the official notices account', () {
      final room = roomAs('@me:example.org', {});

      expect(
        memberActionsFor(room, member(room, officialNoticesUserId)),
        isNot(contains(MemberAction.block)),
      );
    });
  });

  test('removing and banning name the place', () {
    final l10n = englishLocalizations;

    expect(
      MemberAction.remove.label(l10n, RemoveMemberPlace.community),
      l10n.communitiesRemoveFromCommunity,
    );
    expect(
      MemberAction.ban.label(l10n, RemoveMemberPlace.room),
      l10n.roomInfoBanFromRoom,
    );
  });
}
