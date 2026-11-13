import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/avatar_mark.dart';

import '../../helpers/zuno_app.dart';

void main() {
  testWidgets('the mark sits on the bottom-right corner and the avatar keeps '
      'its size', (tester) async {
    await tester.pumpWidget(
      inZunoApp(
        const MarkedAvatar(
          avatar: SizedBox.square(key: Key('avatar'), dimension: 40),
          mark: SizedBox.square(key: Key('mark'), dimension: 16),
        ),
      ),
    );

    expect(tester.getSize(find.byType(MarkedAvatar)), const Size.square(40));
    expect(
      tester.getBottomRight(find.byKey(const Key('mark'))) -
          tester.getBottomRight(find.byKey(const Key('avatar'))),
      const Offset(2, 2),
    );
  });

  testWidgets('with no mark it is the bare avatar', (tester) async {
    await tester.pumpWidget(
      inZunoApp(
        const MarkedAvatar(
          avatar: SizedBox.square(key: Key('avatar'), dimension: 40),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(MarkedAvatar),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });

  for (final (place, surface) in [
    ('a card', const Color(0xFF29251F)),
    ('a sheet', const Color(0xFFF6F2EA)),
  ]) {
    testWidgets('on $place the ring takes the colour it sits on', (
      tester,
    ) async {
      await tester.pumpWidget(
        inZunoApp(
          Material(
            color: surface,
            child: const AvatarMark(icon: Icons.person, color: Colors.black),
          ),
        ),
      );

      final ring = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(Icons.person),
          matching: find.byType(Container),
        ),
      );
      expect((ring.decoration! as BoxDecoration).color, surface);
    });
  }
}
