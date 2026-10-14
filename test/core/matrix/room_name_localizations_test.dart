import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/room_name_localizations.dart';

void main() {
  final names = RoomNameLocalizations(englishLocalizations);

  test('a group with no other members is an empty chat', () {
    expect(names.groupWith(''), 'Empty chat');
    expect(names.groupWith('  '), 'Empty chat');
  });

  test('room-name fallbacks keep their English', () {
    expect(names.groupWith('Alice, Bob'), 'Group with Alice, Bob');
    expect(names.emptyChat, 'Empty chat');
    expect(names.invitedBy('Carol'), 'Invited by Carol');
    expect(names.wasDirectChatDisplayName('Dan'), 'Empty chat (was Dan)');
    expect(names.unknownUser, 'Unknown user');
  });
}
