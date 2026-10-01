import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/client_startup.dart';
import 'package:zuno/features/startup/presentation/startup_failure_page.dart';

void main() {
  Future<List<StartupChoice>> show(WidgetTester tester) async {
    final choices = <StartupChoice>[];
    await tester.pumpWidget(StartupFailureApp(onChoice: choices.add));
    return choices;
  }

  testWidgets('says what happened, that nothing was deleted, and what to '
      'do', (tester) async {
    await show(tester);

    expect(find.text('Zuno could not start'), findsOneWidget);
    expect(find.textContaining('Nothing has been deleted'), findsOneWidget);
    expect(find.textContaining('restart your device'), findsOneWidget);
  });

  testWidgets('Try again is reported once, however often it is '
      'tapped', (tester) async {
    final choices = await show(tester);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.tap(find.text('Try again'), warnIfMissed: false);
    await tester.pump();

    expect(choices, [StartupChoice.tryAgain]);
  });

  testWidgets('starting over asks first, and Cancel deletes nothing', (
    tester,
  ) async {
    final choices = await show(tester);

    await tester.tap(find.text('Start over on this device'));
    await tester.pumpAndSettle();

    expect(find.text('Start over on this device?'), findsOneWidget);
    expect(find.textContaining('Nobody can undo this'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(choices, isEmpty);
    expect(find.text('Start over on this device?'), findsNothing);
  });

  testWidgets('confirming starts over', (tester) async {
    final choices = await show(tester);

    await tester.tap(find.text('Start over on this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete and start over'));
    await tester.pumpAndSettle();

    expect(choices, [StartupChoice.startOver]);
  });

  testWidgets('once a choice is made, the other one is no longer '
      'offered', (tester) async {
    final choices = await show(tester);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.tap(
      find.text('Start over on this device'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Start over on this device?'), findsNothing);
    expect(choices, [StartupChoice.tryAgain]);
  });
}
