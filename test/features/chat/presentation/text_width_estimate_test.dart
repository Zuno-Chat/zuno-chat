import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/text_width_estimate.dart';

void main() {
  Future<double> measure(
    WidgetTester tester,
    String text, {
    double padding = 24,
  }) async {
    late double result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            result = estimateTextWidth(context, text, padding: padding);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('longer text measures wider than shorter text', (tester) async {
    final short = await measure(tester, 'hi');
    final long = await measure(
      tester,
      'this is a much longer message than the other one',
    );
    expect(long, greaterThan(short));
  });

  testWidgets('empty text is exactly the padding', (tester) async {
    expect(await measure(tester, ''), 24);
  });

  testWidgets('a custom padding is honored', (tester) async {
    final defaultPadding = await measure(tester, 'hello');
    final customPadding = await measure(tester, 'hello', padding: 100);
    expect(customPadding - defaultPadding, 100 - 24);
  });

  testWidgets('larger text measures wider than the same text at '
      'normal size', (tester) async {
    Future<double> at(double scale) async {
      late double result;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) {
                result = estimateTextWidth(context, 'hello there');
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return result;
    }

    final normal = await at(1);
    expect(await at(2), greaterThan(normal));
    expect(await at(1), normal);
  });
}
