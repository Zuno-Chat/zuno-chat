import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/load_more_trigger.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('asks for more once when it shows, not on every rebuild', (
    tester,
  ) async {
    var asked = 0;
    final trigger = StatefulBuilder(
      builder: (context, setState) => Column(
        children: [
          TextButton(onPressed: () => setState(() {}), child: const Text('x')),
          LoadMoreTrigger(onVisible: () => asked++),
        ],
      ),
    );
    await tester.pumpWidget(host(trigger));
    await tester.pump();
    expect(asked, 1);

    await tester.tap(find.text('x'));
    await tester.pump();
    await tester.pump();
    expect(asked, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('asks again when it shows anew', (tester) async {
    var asked = 0;
    await tester.pumpWidget(
      host(LoadMoreTrigger(key: const ValueKey(1), onVisible: () => asked++)),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(LoadMoreTrigger(key: const ValueKey(2), onVisible: () => asked++)),
    );
    await tester.pump();

    expect(asked, 2);
  });
}
