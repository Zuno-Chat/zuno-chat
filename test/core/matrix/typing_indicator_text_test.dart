import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/typing_indicator_text.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient());
  });

  User user(String id, String name) => User(id, displayName: name, room: room);

  test('null when nobody is typing', () {
    expect(typingIndicatorText([]), isNull);
  });

  test('one person typing', () {
    expect(typingIndicatorText([user('@a:x', 'Alice')]), 'Alice is typing…');
  });

  test('two people typing', () {
    expect(
      typingIndicatorText([user('@a:x', 'Alice'), user('@b:x', 'Bob')]),
      'Alice and Bob are typing…',
    );
  });

  test('three or more people typing collapses to a generic message', () {
    expect(
      typingIndicatorText([
        user('@a:x', 'Alice'),
        user('@b:x', 'Bob'),
        user('@c:x', 'Carol'),
      ]),
      'Several people are typing…',
    );
  });
}
