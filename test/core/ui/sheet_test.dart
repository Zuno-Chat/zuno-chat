import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/core/ui/sheet.dart';

void main() {
  late KeepClearAreas areas;

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeepClearScope(child: child!),
        home: const Scaffold(body: Text('Chat')),
      ),
    );
    final context = tester.element(find.text('Chat'));
    areas = KeepClearScope.maybeOf(context)!;
    areas.addListener(() {});
    return context;
  }

  testWidgets('keeps the whole sheet clear, drag handle and all, until it '
      'closes', (tester) async {
    final context = await pumpHost(tester);
    expect(areas.bottom, 0);

    final closed = showSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SizedBox(height: 200),
    );
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.bottom, tester.getSize(find.byType(Scaffold)).height);
    expect(sheet.height, greaterThan(200));
    expect(areas.bottom, sheet.height);

    Navigator.of(tester.element(find.byType(BottomSheet))).pop('done');
    await tester.pumpAndSettle();

    expect(await closed, 'done');
    expect(areas.bottom, 0);
  });

  testWidgets('hands its options to the bottom sheet', (tester) async {
    final context = await pumpHost(tester);

    unawaited(
      showSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const Text('Sheet'),
      ),
    );
    await tester.pumpAndSettle();

    final route =
        ModalRoute.of(tester.element(find.text('Sheet')))!
            as ModalBottomSheetRoute<void>;
    expect(route.isScrollControlled, isTrue);
    expect(route.useSafeArea, isTrue);
    expect(route.showDragHandle, isTrue);
  });
}
