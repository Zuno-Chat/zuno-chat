import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/core/ui/card_list_view.dart';

void expectEveryRowOnACard() {
  expect(find.byType(CardListView), findsOneWidget);
  final rows = find.byType(ListTile, skipOffstage: false).evaluate().toList();
  expect(rows, isNotEmpty);
  for (final row in rows) {
    final title = (row.widget as ListTile).title;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => e == row, skipOffstage: false),
        matching: find.byType(CardGroup, skipOffstage: false),
      ),
      findsOneWidget,
      reason: 'a row sits outside every card: $title',
    );
  }
}
