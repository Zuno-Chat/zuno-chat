import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const layoutMatrix = <({String name, Size size, double textScale, bool rtl})>[
  (name: 'small phone', size: Size(360, 640), textScale: 1, rtl: false),
  (
    name: 'smallest phone, 2x text',
    size: Size(320, 568),
    textScale: 2,
    rtl: false,
  ),
  (name: 'landscape', size: Size(640, 360), textScale: 1, rtl: false),
  (
    name: 'landscape, 1.3x text',
    size: Size(640, 360),
    textScale: 1.3,
    rtl: false,
  ),
  (name: 'right to left', size: Size(360, 640), textScale: 1, rtl: true),
];

Future<void> expectSurvivesLayoutMatrix(
  WidgetTester tester,
  Widget Function() build, {
  ThemeData? theme,
  Future<void> Function(String caseName)? afterEach,
}) async {
  addTearDown(tester.view.reset);
  for (final entry in layoutMatrix) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = entry.size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(entry.textScale)),
          child: Directionality(
            textDirection: entry.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: build(),
      ),
    );
    await tester.pump();
    final error = tester.takeException();
    expect(
      error,
      isNull,
      reason:
          '${entry.name}\n'
          '${error is FlutterError ? error.toStringDeep() : ''}',
    );
    await afterEach?.call(entry.name);
  }
}
