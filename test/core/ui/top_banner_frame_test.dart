import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/top_banner_frame.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  static var created = 0;
  static double? top;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.created++;
  }

  @override
  Widget build(BuildContext context) {
    _Probe.top = MediaQuery.paddingOf(context).top;
    return const SizedBox.expand();
  }
}

Widget _frame(List<Widget?> banners) => MediaQuery(
  data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TopBannerFrame(banners: banners, child: const _Probe()),
  ),
);

Widget _banner(String name) =>
    SafeArea(bottom: false, child: SizedBox(key: ValueKey(name), height: 40));

void main() {
  double top(WidgetTester tester, String name) =>
      tester.getTopLeft(find.byKey(ValueKey(name))).dy;

  double contentTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(_Probe)).dy;

  testWidgets('a banner slides in over the content, which keeps its own top '
      'inset and its state and moves down only by what that inset cannot '
      'hide', (tester) async {
    _Probe.created = 0;
    final shown = ValueNotifier(false);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (_, on, _) => _frame([on ? const SizedBox(height: 64) : null]),
      ),
    );
    expect(contentTop(tester), 0);

    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(contentTop(tester), inExclusiveRange(0, 40));

    await tester.pumpAndSettle();
    expect(contentTop(tester), 40);
    expect(_Probe.top, 24);

    shown.value = false;
    await tester.pumpAndSettle();
    expect(contentTop(tester), 0);
    expect(_Probe.created, 1);
  });

  testWidgets('every banner stays clear of the status bar, and one below '
      'another sits right under it', (tester) async {
    await tester.pumpWidget(_frame([_banner('first'), _banner('second')]));

    expect(top(tester, 'first'), 24);
    expect(top(tester, 'second'), 64);
    expect(contentTop(tester), 80);
  });

  testWidgets('a banner arriving above another pushes it down a little each '
      'frame, never under the status bar', (tester) async {
    final first = ValueNotifier(false);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: first,
        builder: (_, on, _) =>
            _frame([on ? _banner('first') : null, _banner('second')]),
      ),
    );
    final tops = [top(tester, 'second')];

    first.value = true;
    for (var frame = 0; frame < 25; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      tops.add(top(tester, 'second'));
    }

    expect(tops.first, 24);
    expect(tops.last, 64);
    for (var frame = 1; frame < tops.length; frame++) {
      expect(tops[frame] - tops[frame - 1], inInclusiveRange(0, 12));
    }
  });

  testWidgets('the part of a banner hidden under the one above it takes no '
      'taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _frame([
        _banner('first'),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: _banner('second'),
        ),
      ]),
    );

    await tester.tapAt(const Offset(100, 50));
    expect(taps, 0);

    await tester.tapAt(const Offset(100, 80));
    expect(taps, 1);
  });
}
