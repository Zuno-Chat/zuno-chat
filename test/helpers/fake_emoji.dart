import 'dart:io';

import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/emoji/emoji_catalog_provider.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

final _english = EmojiNames.fromJson(
  File('packages/zuno_emoji/assets/names/en.json').readAsStringSync(),
);

EmojiCatalog fakeCatalog(EmojiRecents recents, {bool provisional = false}) =>
    EmojiCatalog(
      names: _english,
      english: _english,
      recents: recents,
      undrawable: const {},
      provisional: provisional,
    );

final Override fakeEmojiCatalog = emojiCatalogProvider.overrideWith(
  (ref) async => fakeCatalog(ref.watch(emojiRecentsProvider)),
);

Future<void> showEmojiList(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Show emoji'));
  await tester.pump();
  await tester.pump();
}
