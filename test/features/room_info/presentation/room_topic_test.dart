import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/linkified_text.dart';
import 'package:zuno/features/room_info/presentation/room_topic.dart';

import '../../../helpers/layout_matrix.dart';

const _long =
    'Weekend hikes in and around Lisbon. Routes and meeting points are '
    'posted every Thursday. Be kind, and ask before sharing photos of other '
    'people. Map: https://lisbonhikes.org/map';

void main() {
  Future<void> pumpTopic(
    WidgetTester tester,
    String topic, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: RoomTopic(topic: topic),
          ),
        ),
      ),
    );
  }

  int? shownLines(WidgetTester tester) =>
      tester.widget<LinkifiedText>(find.byType(LinkifiedText)).maxLines;

  testWidgets('a short topic shows in full, centered, with no read more', (
    tester,
  ) async {
    await pumpTopic(tester, 'Weekend hikes');

    expect(find.text('Weekend hikes'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Weekend hikes')).textAlign,
      TextAlign.center,
    );
    expect(find.text('Read more'), findsNothing);
  });

  testWidgets('a long topic stops at three lines with read more', (
    tester,
  ) async {
    await pumpTopic(tester, _long);

    expect(shownLines(tester), 3);
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('read more shows the whole topic and show less folds it', (
    tester,
  ) async {
    await pumpTopic(tester, _long);

    await tester.tap(find.text('Read more'));
    await tester.pump();
    expect(shownLines(tester), isNull);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(shownLines(tester), 3);
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('four short lines fold like one long one', (tester) async {
    await pumpTopic(tester, 'One\nTwo\nThree\nFour');

    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('a topic that fits at normal size folds at large text', (
    tester,
  ) async {
    const medium = 'Weekend hikes around Lisbon, every Saturday';
    await pumpTopic(tester, medium);
    expect(find.text('Read more'), findsNothing);

    await pumpTopic(tester, medium, textScale: 2);
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('a long topic survives the layout matrix', (tester) async {
    await expectSurvivesLayoutMatrix(
      tester,
      () => Scaffold(
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: const [RoomTopic(topic: _long)],
        ),
      ),
    );
  });
}
