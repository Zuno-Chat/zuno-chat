import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/route_settled.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

class _Probe extends StatefulWidget {
  final VoidCallback onSettled;
  const _Probe(this.onSettled);

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with RouteSettled<_Probe> {
  @override
  void onRouteSettled() => widget.onSettled();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(routeSettled ? 'settled' : 'sliding'));
}

void main() {
  testWidgets('a pushed page settles only when its slide has finished', (
    tester,
  ) async {
    var settled = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _Probe(() => settled++)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(settled, 0);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(settled, 1);
  });

  testWidgets('a page with no slide settles after its first frame, once', (
    tester,
  ) async {
    var settled = 0;
    await tester.pumpWidget(MaterialApp(home: _Probe(() => settled++)));
    await tester.pump();
    await tester.pump();
    expect(settled, 1);
  });

  testWidgets('a page closed mid-slide never settles', (tester) async {
    var settled = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        navigatorKey: navigator,
        home: const Scaffold(body: Text('home')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => _Probe(() => settled++)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(settled, 0);
  });
}
