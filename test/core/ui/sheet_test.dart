import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/core/ui/sheet.dart';

void main() {
  late KeepClearAreas areas;

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

  testWidgets('a sheet longer than its share of the screen scrolls to its '
      'last row instead of overflowing', (tester) async {
    final context = await pumpHost(tester);
    int? chosen;

    unawaited(
      showSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 12; i++)
              ListTile(
                title: Text('Row $i'),
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ).then((value) => chosen = value),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Row 11'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Row 11'));
    await tester.pumpAndSettle();

    expect(chosen, 11);
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

  testWidgets('an action sheet answers with the tapped action and paints a '
      'destructive one red', (tester) async {
    final context = await pumpHost(tester);
    final error = Theme.of(context).colorScheme.error;

    final chosen = showActionSheet<String>(
      context,
      title: 'Alice',
      actions: const [
        SheetAction('mute', icon: Icons.mic_off_outlined, label: 'Mute'),
        SheetAction(
          'remove',
          icon: Icons.person_remove_outlined,
          label: 'Remove',
          destructive: true,
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.person_remove_outlined)))
          .color,
      error,
    );
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.mic_off_outlined))).color,
      isNot(error),
    );

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await chosen, 'remove');
  });

  testWidgets('a choice sheet ticks the current choice and answers with the '
      'tapped one', (tester) async {
    final context = await pumpHost(tester);
    String? chosen = 'unset';

    unawaited(
      showChoiceSheet<String>(
        context,
        current: 'b',
        header: 'Applies from now on',
        choices: const [
          SheetChoice('a', label: 'Anyone'),
          SheetChoice('b', label: 'Members', subtitle: 'Only people here'),
        ],
      ).then((value) => chosen = value),
    );
    await tester.pumpAndSettle();

    expect(find.text('Applies from now on'), findsOneWidget);
    expect(find.text('Only people here'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Members'),
        matching: find.byIcon(Icons.check_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_outlined), findsOneWidget);

    await tester.tap(find.text('Anyone'));
    await tester.pumpAndSettle();
    expect(chosen, 'a');
  });
}
