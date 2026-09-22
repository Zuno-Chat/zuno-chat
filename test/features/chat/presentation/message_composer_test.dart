import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/message_composer.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';

void main() {
  late TextEditingController controller;
  late ValueNotifier<Duration> duration;
  late int sends;
  late int probeBuilds;

  setUp(() {
    controller = TextEditingController();
    duration = ValueNotifier(Duration.zero);
    sends = 0;
    probeBuilds = 0;
    addTearDown(controller.dispose);
    addTearDown(duration.dispose);
  });

  Widget harness({bool recording = false}) => MaterialApp(
    theme: zunoLightTheme,
    home: Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Builder(
            builder: (context) {
              probeBuilds++;
              return const SizedBox.shrink();
            },
          ),
          MessageComposer(
            controller: controller,
            onSend: () => sends++,
            onAttach: () {},
            incognitoKeyboard: false,
            isRecording: recording,
            recordingDuration: duration,
            recordingWillCancel: false,
            tapToggleRecording: false,
            onMicPointerDown: (_) {},
            onMicPointerMove: (_) {},
            onMicPointerUp: (_) {},
            onMicPointerCancel: (_) {},
            onCancelRecording: () {},
          ),
        ],
      ),
    ),
  );

  testWidgets('the box grows to five lines, then scrolls', (tester) async {
    await tester.pumpWidget(harness());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 1);
    expect(field.maxLines, 5);
    expect(field.textCapitalization, TextCapitalization.sentences);
    expect(field.decoration!.hintText, 'Message');

    final oneLine = tester.getSize(find.byType(TextField)).height;
    controller.text = List.filled(5, 'line').join('\n');
    await tester.pump();
    final fiveLines = tester.getSize(find.byType(TextField)).height;
    controller.text = List.filled(9, 'line').join('\n');
    await tester.pump();
    final nineLines = tester.getSize(find.byType(TextField)).height;

    expect(fiveLines, greaterThan(oneLine));
    expect(nineLines, fiveLines);
  });

  testWidgets('Enter inserts a new line and does not send', (tester) async {
    await tester.pumpWidget(harness());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textInputAction, TextInputAction.newline);
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.onSubmitted, isNull);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    expect(sends, 0);
  });

  testWidgets('the button sends; it is the mic when the box is empty', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
    expect(find.byType(SendIcon), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(find.byType(SendIcon), findsOneWidget);

    await tester.tap(find.byType(SendIcon));
    expect(sends, 1);
  });

  testWidgets('a recording tick rebuilds only the timer text', (tester) async {
    await tester.pumpWidget(harness(recording: true));
    expect(find.text('00:00'), findsOneWidget);
    final before = probeBuilds;

    duration.value = const Duration(seconds: 7);
    await tester.pump();

    expect(find.text('00:07'), findsOneWidget);
    expect(probeBuilds, before);
  });

  testWidgets('the reply bar names who is answered and can be closed', (
    tester,
  ) async {
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(
          body: ComposeBar(
            title: 'Replying to Dad',
            snippet: 'Can you bring the ladder?',
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('Replying to Dad'));
    expect(title.style!.color, zunoLightTheme.colorScheme.primary);
    expect(title.style!.fontWeight, FontWeight.w500);
    expect(find.text('Can you bring the ladder?'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    expect(cancelled, 1);
  });
}
