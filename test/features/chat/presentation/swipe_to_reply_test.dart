import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/swipe_to_reply.dart';

void main() {
  late int replies;

  Widget harness({bool disableAnimations = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: SwipeToReply(
            onReply: () => replies++,
            child: const SizedBox(
              width: 200,
              height: 48,
              child: ColoredBox(color: Colors.amber, child: Text('hi')),
            ),
          ),
        ),
      ),
    ),
  );

  setUp(() => replies = 0);

  testWidgets('a drag past the threshold replies once', (tester) async {
    await tester.pumpWidget(harness());
    final start = tester.getTopLeft(find.text('hi')).dx;

    await tester.drag(find.text('hi'), const Offset(-90, 0));
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(tester.getTopLeft(find.text('hi')).dx, start);
  });

  testWidgets('a short drag springs back without replying', (tester) async {
    await tester.pumpWidget(harness());
    final start = tester.getTopLeft(find.text('hi')).dx;

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('hi')),
    );
    await gesture.moveBy(const Offset(-25, 0));
    await gesture.moveBy(const Offset(-15, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('hi')).dx, lessThan(start));
    expect(find.byIcon(Icons.reply_outlined), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(replies, 0);
    expect(tester.getTopLeft(find.text('hi')).dx, start);
    expect(find.byIcon(Icons.reply_outlined), findsNothing);
  });

  testWidgets('the drag stops at its limit', (tester) async {
    await tester.pumpWidget(harness());
    final start = tester.getTopLeft(find.text('hi')).dx;

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('hi')),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('hi')).dx,
      closeTo(start - SwipeToReply.maxDrag, 0.01),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a rightward drag does nothing', (tester) async {
    await tester.pumpWidget(harness());
    final start = tester.getTopLeft(find.text('hi')).dx;

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('hi')),
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('hi')).dx, start);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(replies, 0);
  });

  testWidgets('with animations off it snaps back in one frame', (tester) async {
    await tester.pumpWidget(harness(disableAnimations: true));
    final start = tester.getTopLeft(find.text('hi')).dx;

    await tester.drag(find.text('hi'), const Offset(-40, 0));
    await tester.pump();

    expect(tester.getTopLeft(find.text('hi')).dx, start);
  });

  testWidgets('a drag that starts beside the bubble still replies', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeToReply(
            onReply: () => replies++,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [SizedBox(width: 60, height: 40, child: Text('ok'))],
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(300, 20), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(replies, 1);
  });
}
