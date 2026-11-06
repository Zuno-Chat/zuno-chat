import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/src/emoji_names.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('names are parsed in the background the app hands in', () async {
    var ran = 0;
    Future<T> background<T>(T Function() work) async {
      ran++;
      return work();
    }

    final names = await EmojiNames.load('de', background: background);

    expect(ran, 1);
    expect(names.name(indexOf('😀')), 'grinsendes Gesicht');
    expect(names.score(indexOf('😀'), 'grinsend'), isNotNull);
  });
}
