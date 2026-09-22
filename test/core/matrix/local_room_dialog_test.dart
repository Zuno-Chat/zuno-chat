import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/local_room_dialog.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  String? roomId;
  var closed = false;

  Future<void> openDialog(WidgetTester tester) async {
    roomId = null;
    closed = false;
    final client = buildTestClient(userId: '@alice:zuno.chat')
      ..homeserver = Uri.parse('https://matrix.example.org');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              roomId = await showLocalRoomDialog(context, client: client);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('an alias lands on the server name, not the API host', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'general');
    await tester.tap(find.widgetWithText(TextButton, 'Join'));
    await tester.pumpAndSettle();

    expect(roomId, '#general:zuno.chat');
  });

  testWidgets('a room ID lands on the server name too', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Room ID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.tap(find.widgetWithText(TextButton, 'Join'));
    await tester.pumpAndSettle();

    expect(roomId, '!abc123:zuno.chat');
  });

  testWidgets('cancelling yields nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(roomId, isNull);
  });

  testWidgets('an empty local part yields nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Join'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(roomId, isNull);
  });
}
