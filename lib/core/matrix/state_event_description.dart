import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import 'room_updates.dart';

String? describeStateEvent(AppLocalizations l10n, Event event) {
  if (event.redacted) return null;
  final update = describeRoomUpdates(l10n, [event]).firstOrNull;
  if (update != null) return update;
  final sender = event.senderFromMemoryOrFallback.calcDisplayname();
  return switch (event.type) {
    EventTypes.RoomPowerLevels => l10n.matrixStatePermissionsChanged(sender),
    EventTypes.RoomJoinRules => l10n.matrixStateJoinRulesChanged(sender),
    EventTypes.RoomCanonicalAlias => l10n.matrixStateAddressChanged(sender),
    EventTypes.HistoryVisibility => l10n.matrixStateHistoryChanged(sender),
    EventTypes.GuestAccess => l10n.matrixStateGuestAccessChanged(sender),
    EventTypes.Encryption => l10n.matrixStateEncryptionOn(sender),
    EventTypes.RoomTombstone => l10n.matrixStateUpgraded(sender),
    _ => null,
  };
}
