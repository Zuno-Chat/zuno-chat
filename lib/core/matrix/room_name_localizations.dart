import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';

class RoomNameLocalizations extends MatrixDefaultLocalizations {
  const RoomNameLocalizations(this.l10n);

  final AppLocalizations l10n;

  @override
  String get emptyChat => l10n.roomNameEmpty;

  @override
  String groupWith(String displayname) => displayname.trim().isEmpty
      ? l10n.roomNameEmpty
      : l10n.roomNameGroupWith(displayname);

  @override
  String invitedBy(String senderName) => l10n.roomNameInvitedBy(senderName);

  @override
  String wasDirectChatDisplayName(String oldDisplayName) =>
      l10n.roomNameWasDirectChat(oldDisplayName);

  @override
  String get unknownUser => l10n.roomNameUnknownUser;
}
