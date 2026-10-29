import 'package:matrix/matrix.dart';

import '../format/date_labels.dart';
import '../l10n/l10n.dart';
import 'room_roles.dart';

bool isRoomUpdate(Event event, {bool? direct}) {
  if (event.redacted || event.stateKey == null) return false;
  bool isDirect() => direct ?? event.room.isDirectChat;
  if (event.type == EventTypes.RoomMember) {
    return switch (event.roomMemberChangeType) {
      RoomMemberChangeType.leave ||
      RoomMemberChangeType.kick ||
      RoomMemberChangeType.ban => true,
      RoomMemberChangeType.join ||
      RoomMemberChangeType.acceptInvite ||
      RoomMemberChangeType.rejectInvite ||
      RoomMemberChangeType.withdrawInvitation ||
      RoomMemberChangeType.invite ||
      RoomMemberChangeType.unban ||
      RoomMemberChangeType.knock => !isDirect(),
      RoomMemberChangeType.avatar ||
      RoomMemberChangeType.displayname ||
      RoomMemberChangeType.other => false,
    };
  }
  if (event.stateKey != '') return false;
  final shown = event.type == EventTypes.RoomPowerLevels
      ? _roleChanges(event).isNotEmpty
      : _details.contains(event.type);
  return shown && !isDirect();
}

const _details = {
  EventTypes.RoomCreate,
  EventTypes.RoomName,
  EventTypes.RoomTopic,
  EventTypes.RoomAvatar,
};

class RoomUpdateGrouping {
  final List<Event> messages;
  final Map<String, List<Event>> bursts;

  const RoomUpdateGrouping({required this.messages, required this.bursts});
}

RoomUpdateGrouping groupRoomUpdates(List<Event> newestFirst, {bool? direct}) {
  final messages = <Event>[];
  final bursts = <String, List<Event>>{};
  var run = <Event>[];

  void closeRun() {
    if (run.isEmpty) return;
    messages.add(run.last);
    bursts[run.last.eventId] = run.reversed.toList();
    run = [];
  }

  for (final event in newestFirst) {
    if (!isRoomUpdate(event, direct: direct)) {
      closeRun();
      messages.add(event);
      continue;
    }
    if (run.isNotEmpty &&
        calendarDaysBetween(event.originServerTs, run.last.originServerTs) !=
            0) {
      closeRun();
    }
    run.add(event);
  }
  closeRun();
  return RoomUpdateGrouping(messages: messages, bursts: bursts);
}

List<String> describeRoomUpdates(AppLocalizations l10n, List<Event> burst) {
  if (burst.isEmpty) return const [];
  final room = burst.first.room;
  final me = room.client.userID;
  final creators = {
    for (final event in burst)
      if (event.type == EventTypes.RoomCreate) event.senderId,
  };
  final names = <String, String>{};
  final ownActs = <String, List<(int, _Own)>>{};
  final acts = <(_Act, String, bool), _Line>{};
  final roles = <String, (int, RoomRole, String)>{};
  final details = <String, (int, Event)>{};

  for (final (index, event) in burst.indexed) {
    if (event.type == EventTypes.RoomMember) {
      final target = event.stateKey!;
      names[target] = event.asUser.calcDisplayname();
      void own(_Own kind) =>
          ownActs.putIfAbsent(target, () => []).add((index, kind));
      void act(_Act kind) {
        final aboutMe = target == me && event.senderId != me;
        acts
            .putIfAbsent((kind, event.senderId, aboutMe), () => _Line(index))
            .people
            .add(target);
      }

      switch (event.roomMemberChangeType) {
        case RoomMemberChangeType.join || RoomMemberChangeType.acceptInvite:
          if (!creators.remove(target)) own(_Own.joined);
        case RoomMemberChangeType.leave:
          own(_Own.left);
        case RoomMemberChangeType.rejectInvite:
          own(_Own.declined);
        case RoomMemberChangeType.knock:
          own(_Own.knocked);
        case RoomMemberChangeType.invite:
          act(_Act.invited);
        case RoomMemberChangeType.kick:
          act(_Act.removed);
        case RoomMemberChangeType.ban:
          act(_Act.banned);
        case RoomMemberChangeType.unban:
          act(_Act.unbanned);
        case RoomMemberChangeType.withdrawInvitation:
          act(_Act.withdrew);
        case RoomMemberChangeType.avatar ||
            RoomMemberChangeType.displayname ||
            RoomMemberChangeType.other:
          break;
      }
    } else if (event.type == EventTypes.RoomPowerLevels) {
      final changes = _roleChanges(event);
      for (final MapEntry(key: user, value: role) in changes.entries) {
        roles[user] = (roles[user]?.$1 ?? index, role, event.senderId);
      }
    } else if (_details.contains(event.type) && event.stateKey == '') {
      details[event.type] = (details[event.type]?.$1 ?? index, event);
    }
  }

  String nameOf(String userId) =>
      names[userId] ??
      room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();

  final ownLines = <(_Own, bool), _Line>{};
  for (final MapEntry(key: person, value: kinds) in ownActs.entries) {
    final joinedThenLeft =
        kinds.last.$2 == _Own.left &&
        kinds.any((step) => step.$2 == _Own.joined);
    final kind = joinedThenLeft ? _Own.joinedAndLeft : kinds.last.$2;
    ownLines
        .putIfAbsent((kind, person == me), () => _Line(kinds.first.$1))
        .people
        .add(person);
  }

  final roleLines = <(RoomRole, String?), _Line>{};
  for (final MapEntry(key: person, value: (index, role, actor))
      in roles.entries) {
    roleLines
        .putIfAbsent((role, person == me ? null : actor), () => _Line(index))
        .people
        .add(person);
  }

  String people(_Line line) =>
      _people(l10n, [for (final id in line.people) nameOf(id)]);

  String actLine(_Act kind, String actor, bool aboutMe, _Line line) {
    if (aboutMe) return _actOnYou(l10n, kind, nameOf(actor));
    if (actor == me) {
      return _actByYou(l10n, kind, people(line), line.people.length);
    }
    return _act(l10n, kind, nameOf(actor), people(line), line.people.length);
  }

  String roleLine(RoomRole role, String? actor, _Line line) {
    if (actor == null) return _roleYou(l10n, role);
    if (actor == me) {
      return _roleByYou(l10n, role, people(line), line.people.length);
    }
    return _role(l10n, role, nameOf(actor), people(line), line.people.length);
  }

  final lines = <(int, String)>[
    for (final MapEntry(key: (kind, isMe), value: line) in ownLines.entries)
      (
        line.index,
        isMe
            ? _ownYou(l10n, kind)
            : _own(l10n, kind, people(line), line.people.length),
      ),
    for (final MapEntry(key: (kind, actor, aboutMe), value: line)
        in acts.entries)
      (line.index, actLine(kind, actor, aboutMe, line)),
    for (final MapEntry(key: (role, actor), value: line) in roleLines.entries)
      (line.index, roleLine(role, actor, line)),
    for (final (index, event) in details.values)
      (index, _detail(l10n, event, byMe: event.senderId == me)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, text) in lines) text];
}

enum _Own { joined, left, joinedAndLeft, declined, knocked }

enum _Act { invited, removed, banned, unbanned, withdrew }

class _Line {
  final int index;
  final people = <String>{};

  _Line(this.index);
}

Map<String, RoomRole> _roleChanges(Event event) {
  final before = event.prevContent;
  if (before == null) return const {};
  final after = event.content;
  RoomRole roleIn(Map<String, Object?> levels, String userId) =>
      roomRoleForLevel(
        levels.tryGetMap<String, Object?>('users')?.tryGet<int>(userId) ??
            levels.tryGet<int>('users_default') ??
            0,
      );
  final users = {
    ...?before.tryGetMap<String, Object?>('users')?.keys,
    ...?after.tryGetMap<String, Object?>('users')?.keys,
  };
  return {
    for (final user in users)
      if (roleIn(before, user) != roleIn(after, user))
        user: roleIn(after, user),
  };
}

String _people(AppLocalizations l10n, List<String> names) =>
    switch (names.length) {
      1 => names[0],
      2 => l10n.matrixPeopleTwo(names[0], names[1]),
      3 => l10n.matrixPeopleThree(names[0], names[1], names[2]),
      _ => l10n.matrixPeopleMany(names[0], names[1], names.length - 2),
    };

String _own(AppLocalizations l10n, _Own kind, String people, int count) =>
    switch (kind) {
      _Own.joined => l10n.matrixStateJoined(people, count),
      _Own.left => l10n.matrixStateLeft(people, count),
      _Own.joinedAndLeft => l10n.matrixStateJoinedAndLeft(people, count),
      _Own.declined => l10n.matrixStateDeclined(people, count),
      _Own.knocked => l10n.matrixStateKnocked(people, count),
    };

String _ownYou(AppLocalizations l10n, _Own kind) => switch (kind) {
  _Own.joined => l10n.matrixStateJoinedYou,
  _Own.left => l10n.matrixStateLeftYou,
  _Own.joinedAndLeft => l10n.matrixStateJoinedAndLeftYou,
  _Own.declined => l10n.matrixStateDeclinedYou,
  _Own.knocked => l10n.matrixStateKnockedYou,
};

String _act(
  AppLocalizations l10n,
  _Act kind,
  String sender,
  String people,
  int count,
) => switch (kind) {
  _Act.invited => l10n.matrixStateInvited(sender, people, count),
  _Act.removed => l10n.matrixStateRemoved(sender, people, count),
  _Act.banned => l10n.matrixStateBanned(sender, people, count),
  _Act.unbanned => l10n.matrixStateUnbanned(sender, people, count),
  _Act.withdrew => l10n.matrixStateInviteWithdrawn(sender, people, count),
};

String _actByYou(AppLocalizations l10n, _Act kind, String people, int count) =>
    switch (kind) {
      _Act.invited => l10n.matrixStateInvitedByYou(people, count),
      _Act.removed => l10n.matrixStateRemovedByYou(people, count),
      _Act.banned => l10n.matrixStateBannedByYou(people, count),
      _Act.unbanned => l10n.matrixStateUnbannedByYou(people, count),
      _Act.withdrew => l10n.matrixStateInviteWithdrawnByYou(people, count),
    };

String _actOnYou(AppLocalizations l10n, _Act kind, String sender) =>
    switch (kind) {
      _Act.invited => l10n.matrixStateInvitedYou(sender),
      _Act.removed => l10n.matrixStateRemovedYou(sender),
      _Act.banned => l10n.matrixStateBannedYou(sender),
      _Act.unbanned => l10n.matrixStateUnbannedYou(sender),
      _Act.withdrew => l10n.matrixStateInviteWithdrawnYou(sender),
    };

String _role(
  AppLocalizations l10n,
  RoomRole role,
  String sender,
  String people,
  int count,
) => switch (role) {
  RoomRole.admin => l10n.matrixStateMadeAdmin(sender, people, count),
  RoomRole.moderator => l10n.matrixStateMadeModerator(sender, people, count),
  RoomRole.member => l10n.matrixStateMadeMember(sender, people, count),
  RoomRole.readOnly => l10n.matrixStateMadeReadOnly(sender, people, count),
};

String _roleByYou(
  AppLocalizations l10n,
  RoomRole role,
  String people,
  int count,
) => switch (role) {
  RoomRole.admin => l10n.matrixStateMadeAdminByYou(people, count),
  RoomRole.moderator => l10n.matrixStateMadeModeratorByYou(people, count),
  RoomRole.member => l10n.matrixStateMadeMemberByYou(people, count),
  RoomRole.readOnly => l10n.matrixStateMadeReadOnlyByYou(people, count),
};

String _roleYou(AppLocalizations l10n, RoomRole role) => switch (role) {
  RoomRole.admin => l10n.matrixStateMadeAdminYou,
  RoomRole.moderator => l10n.matrixStateMadeModeratorYou,
  RoomRole.member => l10n.matrixStateMadeMemberYou,
  RoomRole.readOnly => l10n.matrixStateMadeReadOnlyYou,
};

String _detail(AppLocalizations l10n, Event event, {required bool byMe}) {
  final sender = event.senderFromMemoryOrFallback.calcDisplayname();
  switch (event.type) {
    case EventTypes.RoomName:
      final name = event.content.tryGet<String>('name') ?? '';
      if (name.isEmpty) {
        return byMe
            ? l10n.matrixStateNameRemovedByYou
            : l10n.matrixStateNameRemoved(sender);
      }
      return byMe
          ? l10n.matrixStateNameChangedByYou(name)
          : l10n.matrixStateNameChanged(sender, name);
    case EventTypes.RoomTopic:
      final topic = event.content.tryGet<String>('topic') ?? '';
      if (topic.isEmpty) {
        return byMe
            ? l10n.matrixStateTopicRemovedByYou
            : l10n.matrixStateTopicRemoved(sender);
      }
      return byMe
          ? l10n.matrixStateTopicChangedByYou
          : l10n.matrixStateTopicChanged(sender);
    case EventTypes.RoomAvatar:
      final url = event.content.tryGet<String>('url') ?? '';
      if (url.isEmpty) {
        return byMe
            ? l10n.matrixStateAvatarRemovedByYou
            : l10n.matrixStateAvatarRemoved(sender);
      }
      return byMe
          ? l10n.matrixStateAvatarChangedByYou
          : l10n.matrixStateAvatarChanged(sender);
    default:
      return byMe
          ? l10n.matrixStateCreatedByYou
          : l10n.matrixStateCreated(sender);
  }
}
