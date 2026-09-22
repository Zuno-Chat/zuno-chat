import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/card_list_view.dart';

void main() {
  Widget host(Widget child, {double bottomInset = 0}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
      child: Scaffold(body: child),
    ),
  );

  testWidgets('keeps the last child clear of the navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const CardListView(children: [SizedBox(height: 40)]),
        bottomInset: 48,
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.padding, const EdgeInsets.only(top: 4, bottom: 64));
  });

  testWidgets('a scrollable inside does not add the navigation bar again', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CardListView(
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              children: const [SizedBox(key: ValueKey('cell'))],
            ),
            const SizedBox(key: ValueKey('after'), height: 10),
          ],
        ),
        bottomInset: 48,
      ),
    );

    final cellBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('cell')))
        .dy;
    final afterTop = tester.getTopLeft(find.byKey(const ValueKey('after'))).dy;
    expect(afterTop - cellBottom, closeTo(0, 0.01));
  });

  testWidgets('passes the scroll physics on', (tester) async {
    await tester.pumpWidget(
      host(
        const CardListView(
          physics: AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: 40)],
        ),
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.physics, isA<AlwaysScrollableScrollPhysics>());
  });
}
