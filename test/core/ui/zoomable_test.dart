import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zoomable.dart';

import '../../helpers/zoom_gestures.dart';

void main() {
  late int taps;
  late List<bool> zooms;
  final content = find.byKey(const Key('content'));

  setUp(() {
    taps = 0;
    zooms = [];
  });

  Future<void> pumpZoomable(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Zoomable(
        onTap: () => taps++,
        onZoomChanged: zooms.add,
        child: const ColoredBox(key: Key('content'), color: Colors.black),
      ),
    ),
  );

  double scale(WidgetTester tester) => zoomOf(tester, content);

  Future<void> doubleTap(WidgetTester tester) =>
      doubleTapAt(tester, tester.getCenter(content));

  testWidgets('double-tap zooms in to 2.5x and double-tap again zooms back '
      'out', (tester) async {
    await pumpZoomable(tester);

    await doubleTap(tester);
    expect(scale(tester), closeTo(2.5, 0.001));
    expect(zooms, [true]);

    await doubleTap(tester);
    expect(scale(tester), closeTo(1, 0.001));
    expect(zooms, [true, false]);
    expect(taps, 0);
  });

  testWidgets('a single tap reaches onTap after the double-tap window, '
      'zoomed in or not', (tester) async {
    await pumpZoomable(tester);

    await tester.tap(content);
    await tester.pump(kDoubleTapTimeout);
    expect(taps, 1);
    expect(scale(tester), 1);

    await doubleTap(tester);
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(content);
    await tester.pump(kDoubleTapTimeout);
    expect(taps, 2);
    expect(scale(tester), closeTo(2.5, 0.001));
  });

  testWidgets('a pinch zooms in around the fingers', (tester) async {
    await pumpZoomable(tester);
    const focal = Offset(200, 150);

    await pinch(
      tester,
      from: [focal - const Offset(50, 0), focal + const Offset(50, 0)],
      to: [focal - const Offset(150, 0), focal + const Offset(150, 0)],
    );

    expect(scale(tester), closeTo(3, 0.01));
    expect(tester.getRect(content).topLeft, offsetMoreOrLessEquals(focal * -2));
    expect(zooms, [true]);
  });

  testWidgets('a pinch stops at 5x and never shrinks below the screen', (
    tester,
  ) async {
    await pumpZoomable(tester);
    final center = tester.getCenter(content);

    await pinch(
      tester,
      from: [center - const Offset(20, 0), center + const Offset(20, 0)],
      to: [center - const Offset(300, 0), center + const Offset(300, 0)],
    );
    expect(scale(tester), closeTo(5, 0.001));

    await pinch(
      tester,
      from: [center - const Offset(300, 0), center + const Offset(300, 0)],
      to: [center - const Offset(10, 0), center + const Offset(10, 0)],
    );
    expect(scale(tester), closeTo(1, 0.001));
    expect(
      tester.getRect(content).topLeft,
      offsetMoreOrLessEquals(Offset.zero),
    );
    expect(zooms, [true, false]);
  });

  testWidgets('zoomed in, one finger pans and stops at the edge', (
    tester,
  ) async {
    await pumpZoomable(tester);
    await doubleTap(tester);
    final zoomed = tester.getRect(content);

    await slide(tester, tester.getCenter(content), const Offset(0, -100));
    expect(zoomed.top - tester.getRect(content).top, greaterThan(50));

    await slide(tester, tester.getCenter(content), const Offset(2000, 0));
    expect(tester.getRect(content).left, closeTo(0, 0.001));
    expect(scale(tester), closeTo(2.5, 0.001));
  });

  testWidgets('zoomed in, a fling glides on after the finger lifts', (
    tester,
  ) async {
    await pumpZoomable(tester);
    await doubleTap(tester);

    await tester.fling(content, const Offset(-100, 0), 1000);
    await tester.pump();
    final released = tester.getRect(content).left;
    await tester.pump(const Duration(seconds: 1));

    expect(tester.getRect(content).left, lessThan(released - 50));
  });

  testWidgets('not zoomed in, one finger leaves it in place', (tester) async {
    await pumpZoomable(tester);

    await tester.drag(content, const Offset(-300, 200));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.getRect(content).topLeft, Offset.zero);
    expect(zooms, isEmpty);
  });
}
