import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/trailing_action_row.dart';

void main() {
  const main = Key('main');
  const action = Key('action');

  Future<void> pumpRow(
    WidgetTester tester, {
    required double width,
    TextDirection direction = TextDirection.ltr,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: TrailingActionRow(
            main: const SizedBox(key: main, height: 52),
            action: const SizedBox(key: action, width: 80, height: 40),
          ),
        ),
      ),
    ),
  );

  testWidgets('the action sits at the end of the row, the main part takes '
      'the rest', (tester) async {
    await pumpRow(tester, width: 300);

    expect(
      tester.getRect(find.byKey(main)),
      const Rect.fromLTWH(0, 0, 208, 52),
    );
    expect(
      tester.getRect(find.byKey(action)),
      const Rect.fromLTWH(220, 6, 80, 40),
    );
    expect(tester.getSize(find.byType(TrailingActionRow)).height, 52);
  });

  testWidgets('when the main part would be narrower than the action, the '
      'action moves below it, at the end', (tester) async {
    await pumpRow(tester, width: 160);

    expect(
      tester.getRect(find.byKey(main)),
      const Rect.fromLTWH(0, 0, 160, 52),
    );
    expect(
      tester.getRect(find.byKey(action)),
      const Rect.fromLTWH(80, 56, 80, 40),
    );
    expect(tester.getSize(find.byType(TrailingActionRow)).height, 96);
  });

  testWidgets('right to left puts the action on the left', (tester) async {
    await pumpRow(tester, width: 300, direction: TextDirection.rtl);

    expect(
      tester.getRect(find.byKey(action)),
      const Rect.fromLTWH(0, 6, 80, 40),
    );
    expect(
      tester.getRect(find.byKey(main)),
      const Rect.fromLTWH(92, 0, 208, 52),
    );
  });
}
