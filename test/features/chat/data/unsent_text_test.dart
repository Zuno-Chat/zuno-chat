import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/data/unsent_text.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  final me = buildTestClient(userId: '@me:example.org');
  final chat = buildTestRoom(me, id: '!a:example.org');

  test('keeps what was typed in a chat for that chat', () {
    final unsent = UnsentText()..keep(chat, 'half a thought');

    expect(unsent.textOf(chat), 'half a thought');
    expect(unsent.textOf(buildTestRoom(me, id: '!b:example.org')), '');
  });

  test('keeps it for the account that typed it', () {
    final other = buildTestClient(userId: '@other:example.org');
    final unsent = UnsentText()..keep(chat, 'half a thought');

    expect(unsent.textOf(buildTestRoom(other, id: chat.id)), '');
  });

  test('forgets text that is only blank', () {
    final unsent = UnsentText()
      ..keep(chat, 'half a thought')
      ..keep(chat, '  ');

    expect(unsent.textOf(chat), '');
  });
}
