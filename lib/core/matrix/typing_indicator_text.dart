import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';

String? typingIndicatorText(AppLocalizations l10n, List<User> typingUsers) {
  if (typingUsers.isEmpty) return null;
  if (typingUsers.length == 1) {
    return l10n.matrixTypingOne(typingUsers.first.calcDisplayname());
  }
  if (typingUsers.length == 2) {
    return l10n.matrixTypingTwo(
      typingUsers[0].calcDisplayname(),
      typingUsers[1].calcDisplayname(),
    );
  }
  return l10n.matrixTypingSeveral;
}
