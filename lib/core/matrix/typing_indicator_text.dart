import 'package:matrix/matrix.dart';

String? typingIndicatorText(List<User> typingUsers) {
  if (typingUsers.isEmpty) return null;
  if (typingUsers.length == 1) {
    return '${typingUsers.first.calcDisplayname()} is typing…';
  }
  if (typingUsers.length == 2) {
    return '${typingUsers[0].calcDisplayname()} and ${typingUsers[1].calcDisplayname()} are typing…';
  }
  return 'Several people are typing…';
}
