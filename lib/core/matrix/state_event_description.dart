import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';

String? describeStateEvent(AppLocalizations l10n, Event event) {
  final sender = event.senderFromMemoryOrFallback.calcDisplayname();
  final stateKey = event.stateKey ?? '';

  switch (event.type) {
    case EventTypes.RoomMember:
      final target = event.room
          .unsafeGetUserFromMemoryOrFallback(stateKey)
          .calcDisplayname();
      return switch (event.content.tryGet<String>('membership')) {
        'join' => l10n.matrixStateJoined(target),
        'leave' =>
          stateKey == event.senderId
              ? l10n.matrixStateLeft(target)
              : l10n.matrixStateRemoved(sender, target),
        'invite' => l10n.matrixStateInvited(sender, target),
        'ban' => l10n.matrixStateBanned(sender, target),
        'knock' => l10n.matrixStateKnocked(target),
        _ => l10n.matrixStateMembershipUpdated(sender, target),
      };
    case EventTypes.RoomName:
      final name = event.content.tryGet<String>('name');
      return (name == null || name.isEmpty)
          ? l10n.matrixStateNameRemoved(sender)
          : l10n.matrixStateNameChanged(sender, name);
    case EventTypes.RoomTopic:
      final topic = event.content.tryGet<String>('topic');
      return (topic == null || topic.isEmpty)
          ? l10n.matrixStateTopicRemoved(sender)
          : l10n.matrixStateTopicChanged(sender, topic);
    case EventTypes.RoomAvatar:
      return l10n.matrixStateAvatarChanged(sender);
    case EventTypes.RoomCreate:
      return l10n.matrixStateCreated(sender);
    case EventTypes.RoomPowerLevels:
      return l10n.matrixStatePermissionsChanged(sender);
    case EventTypes.RoomJoinRules:
      return l10n.matrixStateJoinRulesChanged(sender);
    case EventTypes.RoomCanonicalAlias:
      return l10n.matrixStateAddressChanged(sender);
    case EventTypes.HistoryVisibility:
      return l10n.matrixStateHistoryChanged(sender);
    case EventTypes.GuestAccess:
      return l10n.matrixStateGuestAccessChanged(sender);
    case EventTypes.Encryption:
      return l10n.matrixStateEncryptionOn(sender);
    case EventTypes.RoomTombstone:
      return l10n.matrixStateUpgraded(sender);
    default:
      return null;
  }
}
