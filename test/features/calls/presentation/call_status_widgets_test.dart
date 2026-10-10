import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/features/calls/presentation/call_status_widgets.dart';

import '../../../helpers/zuno_app.dart';

void main() {
  testWidgets('good quality renders nothing', (tester) async {
    await tester.pumpWidget(
      inZunoApp(const ConnectionQualityPill(quality: CallQuality.good)),
    );
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('degraded says Weak connection, to screen readers too', (
    tester,
  ) async {
    await tester.pumpWidget(
      inZunoApp(const ConnectionQualityPill(quality: CallQuality.degraded)),
    );
    expect(find.text('Weak connection'), findsOneWidget);
    expect(find.bySemanticsLabel('Weak connection'), findsOneWidget);
  });

  testWidgets('poor says video is reduced', (tester) async {
    await tester.pumpWidget(
      inZunoApp(const ConnectionQualityPill(quality: CallQuality.poor)),
    );
    expect(find.text('Poor connection, video reduced'), findsOneWidget);
  });

  testWidgets('reconnecting notice shows the copy and a spinner, and tells '
      'screen readers', (tester) async {
    await tester.pumpWidget(inZunoApp(const ReconnectingNotice()));
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Reconnecting…'), findsOneWidget);
  });

  testWidgets('encrypting label adds a hint after the delay', (tester) async {
    await tester.pumpWidget(
      inZunoApp(const EncryptingLabel(hintAfter: Duration(seconds: 8))),
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
      inZunoApp(
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

  for (final direction in TextDirection.values) {
    testWidgets('the confirm pill points forward in ${direction.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: ConfirmPersonPill(
                name: '@sam',
                overVideo: false,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    });
  }
}
