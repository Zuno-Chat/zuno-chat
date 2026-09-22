import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/features/calls/presentation/call_status_widgets.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('good quality renders nothing', (tester) async {
    await tester.pumpWidget(
      wrap(const ConnectionQualityPill(quality: CallQuality.good)),
    );
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('degraded says Weak connection', (tester) async {
    await tester.pumpWidget(
      wrap(const ConnectionQualityPill(quality: CallQuality.degraded)),
    );
    expect(find.text('Weak connection'), findsOneWidget);
  });

  testWidgets('poor says video is reduced', (tester) async {
    await tester.pumpWidget(
      wrap(const ConnectionQualityPill(quality: CallQuality.poor)),
    );
    expect(find.text('Poor connection, video reduced'), findsOneWidget);
  });

  testWidgets('reconnecting notice shows the copy and a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const ReconnectingNotice()));
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('pill and notice expose semantics labels', (tester) async {
    await tester.pumpWidget(
      wrap(const ConnectionQualityPill(quality: CallQuality.degraded)),
    );
    expect(find.bySemanticsLabel('Weak connection'), findsOneWidget);
    await tester.pumpWidget(wrap(const ReconnectingNotice()));
    expect(find.bySemanticsLabel('Reconnecting…'), findsOneWidget);
  });

  testWidgets('encrypting label adds a hint after the delay', (tester) async {
    await tester.pumpWidget(
      wrap(const EncryptingLabel(hintAfter: Duration(seconds: 8))),
    );
    expect(find.text('Encrypting…'), findsOneWidget);
    expect(find.textContaining('Still encrypting'), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    expect(
      find.text('Still encrypting. If this continues, hang up and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('the encrypting hint stays inside a narrow local tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 100,
          height: 140,
          child: EncryptingLabel(hintAfter: Duration(seconds: 8)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 8));

    final hint = tester.widget<Text>(find.text(EncryptingLabel.hint));
    expect(hint.maxLines, 3);
    expect(hint.overflow, TextOverflow.ellipsis);
    expect(hint.textAlign, TextAlign.end);
    expect(tester.takeException(), isNull);
  });
}
