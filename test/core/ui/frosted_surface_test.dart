import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/frosted_surface.dart';
import 'package:zuno/core/ui/zuno_colors.dart';

void main() {
  testWidgets('blurs what is behind it and tints it', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: FrostedSurface(child: SizedBox(width: 40, height: 40)),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    final tints = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .map((decoration) => decoration.color);
    expect(tints, contains(frostedFillColor));
  });

  testWidgets('a pill clips to a rounded rectangle, a circle to an oval', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Center(
        child: FrostedSurface(child: SizedBox(width: 80, height: 40)),
      ),
    );
    expect(find.byType(ClipRRect), findsOneWidget);

    await tester.pumpWidget(
      const Center(
        child: FrostedSurface(
          circle: true,
          child: SizedBox.square(dimension: 40),
        ),
      ),
    );
    expect(find.byType(ClipOval), findsOneWidget);
  });
}
