import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/corner_snap.dart';

void main() {
  const bounds = Rect.fromLTRB(8, 88, 352, 616);
  const size = Size(108, 144);
  const spots = CornerSpots(bounds: bounds, size: size);

  test('each corner pins the box inside the bounds', () {
    expect(spots.of(SnapCorner.topRight), const Offset(244, 88));
    expect(spots.of(SnapCorner.bottomLeft), const Offset(8, 472));
  });

  test('with no room left, a bottom corner stops at the top', () {
    expect(
      const CornerSpots(
        bounds: Rect.fromLTRB(8, 88, 352, 150),
        size: size,
      ).of(SnapCorner.bottomLeft),
      const Offset(8, 88),
    );
  });

  test('a released box goes to the corner nearest its center', () {
    expect(spots.nearest(const Offset(46, 428)), SnapCorner.bottomLeft);
    expect(spots.nearest(const Offset(246, 28)), SnapCorner.topRight);
  });

  group('around an area to keep clear', () {
    const header = Rect.fromLTRB(8, 88, 200, 180);
    const clear = CornerSpots(bounds: bounds, size: size, keepClear: header);

    test('a corner it covers drops just below it', () {
      expect(clear.of(SnapCorner.topLeft), const Offset(8, 180));
    });

    test('a corner it does not cover stays put', () {
      expect(clear.of(SnapCorner.topRight), const Offset(244, 88));
      expect(clear.of(SnapCorner.bottomLeft), const Offset(8, 472));
    });

    test('with no room below it, the corner stays put', () {
      expect(
        const CornerSpots(
          bounds: Rect.fromLTRB(8, 88, 352, 300),
          size: size,
          keepClear: header,
        ).of(SnapCorner.topLeft),
        const Offset(8, 88),
      );
    });
  });

  group('the box on screen', () {
    late List<SnapCorner> reported;
    late int taps;

    setUp(() {
      reported = [];
      taps = 0;
    });

    final box = find.byKey(const ValueKey('box'));

    Future<void> pump(
      WidgetTester tester, {
      bool reduceMotion = false,
      bool insideLongPress = false,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      var corner = SnapCorner.topRight;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: StatefulBuilder(
              builder: (context, setState) {
                final spot = spots.of(corner);
                final stack = Stack(
                  children: [
                    Positioned(
                      left: spot.dx,
                      top: spot.dy,
                      width: size.width,
                      height: size.height,
                      child: CornerSnap(
                        corner: corner,
                        onCornerChanged: (next) => setState(() {
                          corner = next;
                          reported.add(next);
                        }),
                        spots: () => spots,
                        onTap: () => taps++,
                        child: const ColoredBox(
                          key: ValueKey('box'),
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                );
                return insideLongPress
                    ? GestureDetector(onLongPress: () {}, child: stack)
                    : stack;
              },
            ),
          ),
        ),
      );
    }

    Offset shownAt(WidgetTester tester) => tester.getTopLeft(box);

    testWidgets('let go, it glides to the nearest corner and reports it', (
      tester,
    ) async {
      await pump(tester);

      await tester.drag(find.byType(CornerSnap), const Offset(-200, 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownAt(tester), isNot(const Offset(8, 472)));
      await tester.pumpAndSettle();

      expect(shownAt(tester), const Offset(8, 472));
      expect(reported, [SnapCorner.bottomLeft]);
    });

    testWidgets('let go near where it started, it goes back without a report', (
      tester,
    ) async {
      await pump(tester);

      await tester.drag(find.byType(CornerSnap), const Offset(-40, 60));
      await tester.pumpAndSettle();

      expect(shownAt(tester), const Offset(244, 88));
      expect(reported, isEmpty);
    });

    testWidgets('with animations off it lands at once', (tester) async {
      await pump(tester, reduceMotion: true);

      await tester.drag(find.byType(CornerSnap), const Offset(-200, 400));
      await tester.pump();

      expect(shownAt(tester), const Offset(8, 472));
    });

    testWidgets('a tap is a tap, not a move', (tester) async {
      await pump(tester);

      await tester.tap(find.byType(CornerSnap));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(shownAt(tester), const Offset(244, 88));
      expect(reported, isEmpty);
    });

    testWidgets('a touch taken over by another gesture leaves it where it '
        'is', (tester) async {
      await pump(tester, insideLongPress: true);
      await tester.drag(find.byType(CornerSnap), const Offset(-200, 400));
      await tester.pumpAndSettle();

      final press = await tester.startGesture(tester.getCenter(box));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await press.up();
      await tester.pump();

      expect(shownAt(tester), const Offset(8, 472));
    });

    testWidgets('a screen reader moves it to any other corner', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      const toBottomLeft = CustomSemanticsAction(label: 'Move to bottom left');
      final node = tester.getSemantics(find.byType(CornerSnap));

      expect(
        node,
        isSemantics(
          customActions: const [
            CustomSemanticsAction(label: 'Move to top left'),
            toBottomLeft,
            CustomSemanticsAction(label: 'Move to bottom right'),
          ],
        ),
      );
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(toBottomLeft),
      );
      await tester.pumpAndSettle();

      expect(shownAt(tester), const Offset(8, 472));
      expect(reported, [SnapCorner.bottomLeft]);
      semantics.dispose();
    });
  });
}
