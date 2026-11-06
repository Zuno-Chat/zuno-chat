import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno_emoji/zuno_emoji.dart';

import 'helpers.dart';

const _labels = EmojiLabels(
  categories: {
    EmojiCategory.smileysPeople: 'Smileys',
    EmojiCategory.animalsNature: 'Animals',
    EmojiCategory.foodDrink: 'Food',
    EmojiCategory.travelPlaces: 'Travel',
    EmojiCategory.activities: 'Activities',
    EmojiCategory.objects: 'Objects',
    EmojiCategory.symbols: 'Symbols',
    EmojiCategory.flags: 'Flags',
  },
  recent: 'Recent',
  search: 'Search emoji',
  noResults: 'No emoji found',
  noRecents: 'Nothing yet',
  backspace: 'Delete',
  closeSearch: 'Back to all emoji',
);

void main() {
  late EmojiRecents recents;
  late List<String> picked;

  setUp(() {
    recents = EmojiRecents(MemoryEmojiStore());
    picked = [];
  });

  EmojiCatalog catalog({Set<String> undrawable = const {}}) => EmojiCatalog(
    names: realNames('de'),
    english: realNames('en'),
    recents: recents,
    undrawable: undrawable,
  );

  Future<void> pump(
    WidgetTester tester, {
    EmojiCatalog? withCatalog,
    VoidCallback? onBackspace,
    EmojiSearchLayout layout = EmojiSearchLayout.grid,
    ValueNotifier<bool>? searching,
    bool shown = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 320,
          child: TickerMode(
            enabled: shown,
            child: EmojiPicker(
              catalog: withCatalog ?? catalog(),
              labels: _labels,
              onSelected: picked.add,
              onBackspace: onBackspace,
              searchLayout: layout,
              searching: searching,
              searchFieldBuilder: (context, controller, focusNode, hint) =>
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(hintText: hint),
                  ),
            ),
          ),
        ),
      ),
    ),
  );

  Finder grid() => find.byType(Scrollable).last;

  Future<void> reveal(WidgetTester tester, String emoji) async {
    await tester.scrollUntilVisible(find.text(emoji), 200, scrollable: grid());
    await tester.ensureVisible(find.text(emoji));
    await tester.pumpAndSettle();
  }

  testWidgets('starts with recent emoji, then the categories in order', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Nothing yet'), findsOneWidget);
    final tabs = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message)
        .toList();
    expect(tabs, containsAllInOrder(['Recent', 'Smileys', 'Animals', 'Flags']));
  });

  testWidgets('tapping an emoji picks it and remembers it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('😀'));
    expect(picked, ['😀']);
    expect(recents.items, ['😀']);
  });

  testWidgets('recent emoji stay put while the picker is open', (tester) async {
    await recents.add('😃');
    await pump(tester);
    expect(find.text('😃'), findsNWidgets(2));
    await tester.tap(find.text('😀'));
    await tester.pump();
    expect(find.text('😀'), findsOneWidget);
  });

  testWidgets('a category tab jumps to that category', (tester) async {
    await pump(tester);
    expect(find.text('🐶'), findsNothing);
    await tester.tap(find.byTooltip('Animals'));
    await tester.pumpAndSettle();
    expect(find.text('Animals'), findsOneWidget);
    expect(find.text('🐵'), findsOneWidget);
  });

  testWidgets('leaves out emoji the device cannot draw', (tester) async {
    await pump(tester, withCatalog: catalog(undrawable: {'😃'}));
    expect(find.text('😀'), findsOneWidget);
    expect(find.text('😃'), findsNothing);
  });

  testWidgets('long press picks a skin tone and remembers it', (tester) async {
    await pump(tester);
    await reveal(tester, '👋');
    await tester.longPress(find.text('👋'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👋🏽'));
    await tester.pumpAndSettle();
    expect(picked, ['👋🏽']);
    expect(find.text('👋🏽'), findsOneWidget);
    expect(find.text('👋'), findsNothing);
  });

  testWidgets('two people get a tone each', (tester) async {
    final kiss = catalog().entryOf('💏')!;
    await pump(tester);
    await reveal(tester, '💏');
    await tester.longPress(find.text('💏'));
    await tester.pumpAndSettle();
    expect(find.text(kiss.variants[24]), findsOneWidget);
    await tester.tap(find.text(kiss.variants[4]));
    await tester.pumpAndSettle();
    expect(picked, [kiss.variants[4]]);
  });

  testWidgets('a long press on an emoji without tones just picks it', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('😀'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(find.text('😀'), findsOneWidget);
    expect(picked, ['😀']);
  });

  testWidgets('labels each emoji for screen readers in the app language', (
    tester,
  ) async {
    await pump(tester);
    expect(find.bySemanticsLabel('grinsendes Gesicht'), findsOneWidget);
  });

  testWidgets('search finds emoji and says when nothing matches', (
    tester,
  ) async {
    final searching = ValueNotifier(false);
    addTearDown(searching.dispose);
    await pump(tester, searching: searching);
    await tester.tap(find.byTooltip('Search emoji'));
    await tester.pump();
    expect(searching.value, isTrue);
    await tester.enterText(find.byType(TextField), 'herz');
    await tester.pump();
    expect(find.text('❤️'), findsOneWidget);
    await tester.tap(find.text('❤️'));
    expect(picked, ['❤️']);
    await tester.enterText(find.byType(TextField), 'zzzzqq');
    await tester.pump();
    expect(find.text('No emoji found'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to all emoji'));
    await tester.pump();
    expect(searching.value, isFalse);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the host can close the search', (tester) async {
    final searching = ValueNotifier(false);
    addTearDown(searching.dispose);
    await pump(tester, searching: searching, layout: EmojiSearchLayout.row);
    await tester.tap(find.byTooltip('Search emoji'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    searching.value = false;
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Search emoji'), findsOneWidget);
  });

  testWidgets('an empty search shows the recent emoji', (tester) async {
    await recents.add('👋🏽');
    await pump(tester, layout: EmojiSearchLayout.row);
    await tester.tap(find.byTooltip('Search emoji'));
    await tester.pump();

    final row = find.ancestor(
      of: find.text('👋🏽'),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.widget<Scrollable>(row.first).axisDirection,
      AxisDirection.right,
    );
    await tester.tap(find.text('👋🏽'));
    expect(picked, ['👋🏽']);

    await tester.enterText(find.byType(TextField), 'herz');
    await tester.pump();
    expect(find.text('👋🏽'), findsNothing);
  });

  testWidgets('row search shows one row of results above the field', (
    tester,
  ) async {
    await pump(tester, layout: EmojiSearchLayout.row);
    await tester.tap(find.byTooltip('Search emoji'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'herz');
    await tester.pump();
    final heart = tester.getRect(find.text('❤️'));
    final field = tester.getRect(find.byType(TextField));
    expect(heart.bottom, lessThanOrEqualTo(field.top));
    final row = find.ancestor(
      of: find.text('❤️'),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.widget<Scrollable>(row.first).axisDirection,
      AxisDirection.right,
    );
  });

  testWidgets('backspace shows only when the host can delete', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Delete'), findsNothing);
    var deleted = 0;
    await pump(tester, onBackspace: () => deleted++);
    await tester.tap(find.byTooltip('Delete'));
    expect(deleted, 1);
  });

  testWidgets('large text on a small phone fits without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const longLabels = EmojiLabels(
      categories: {
        EmojiCategory.smileysPeople: 'Smileys und Personen mit langem Namen',
        EmojiCategory.animalsNature: 'Tiere',
        EmojiCategory.foodDrink: 'Essen',
        EmojiCategory.travelPlaces: 'Reisen',
        EmojiCategory.activities: 'Aktivitäten',
        EmojiCategory.objects: 'Objekte',
        EmojiCategory.symbols: 'Symbole',
        EmojiCategory.flags: 'Flaggen',
      },
      recent: 'Zuletzt verwendet',
      search: 'Emojis suchen',
      noResults: 'Keine Emojis gefunden, versuche ein anderes Wort',
      noRecents: 'Noch keine zuletzt verwendeten Emojis in dieser Liste',
      backspace: 'Löschen',
      closeSearch: 'Zurück zu allen Emojis',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              height: 300,
              child: EmojiPicker(
                catalog: catalog(),
                labels: longLabels,
                onSelected: picked.add,
                searchFieldBuilder: (context, controller, focusNode, hint) =>
                    TextField(controller: controller, focusNode: focusNode),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    void fits(String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason: text,
      );
    }

    fits('Zuletzt verwendet');
    fits('Noch keine zuletzt verwendeten Emojis in dieser Liste');
    await tester.tap(find.byTooltip('Tiere'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Tiere'), findsWidgets);
  });

  testWidgets('the grid stays built while searching', (tester) async {
    await pump(tester, layout: EmojiSearchLayout.row);
    await tester.tap(find.byTooltip('Animals'));
    await tester.pumpAndSettle();
    expect(find.text('🐵'), findsOneWidget);

    await tester.tap(find.byTooltip('Search emoji'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back to all emoji'));
    await tester.pump();

    expect(find.text('🐵'), findsOneWidget);
    expect(find.text('😀'), findsNothing);
  });

  testWidgets('recent emoji catch up when a kept picker shows again', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('😃'));
    await tester.pump();
    expect(find.text('😃'), findsOneWidget);

    await pump(tester, shown: false);
    await pump(tester);

    expect(find.text('😃'), findsNWidgets(2));
  });
}
