import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/upload_http_client.dart';
import 'package:zuno/features/chat/presentation/not_sent.dart';
import 'package:zuno/features/chat/presentation/send_icon.dart';

import 'room_page_harness.dart';

void main() {
  setUp(rootBundle.clear);

  Future<List<Map<String, Object?>>> send(
    WidgetTester tester,
    String text,
  ) async {
    final harness = RoomPageHarness(db: SendingFakeDatabaseApi());
    await harness.pumpRoomPage(tester);
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byType(SendIcon));
    await harness.settle(tester);
    return harness.sent;
  }

  testWidgets('markdown characters are sent as typed', (tester) async {
    final sent = await send(tester, '**bold** and `code`');

    expect(sent.single['body'], '**bold** and `code`');
    expect(sent.single.containsKey('formatted_body'), isFalse);
  });

  testWidgets('a leading slash is sent as text', (tester) async {
    final sent = await send(tester, '/me waves');

    expect(sent.single['msgtype'], MessageTypes.Text);
    expect(sent.single['body'], '/me waves');
  });

  testWidgets('a mention still notifies without a formatted body', (
    tester,
  ) async {
    final sent = await send(tester, 'hi @bob:example.org');

    expect(sent.single['m.mentions'], {
      'user_ids': ['@bob:example.org'],
    });
    expect(sent.single.containsKey('formatted_body'), isFalse);
  });

  testWidgets('a message whose post never gets an answer shows as not sent '
      'once nothing has moved for the stall limit', (tester) async {
    final harness =
        RoomPageHarness(db: SendingFakeDatabaseApi(), sendsGiveUpAtOnce: true)
          ..respond = (request) => request.url.path.contains('/send/')
              ? Completer<http.Response?>().future
              : null;
    await harness.pumpRoomPage(tester);
    await tester.enterText(find.byType(TextField), 'anyone there?');
    await tester.pump();
    await tester.tap(find.byType(SendIcon));
    await harness.settle(tester);
    expect(find.byType(NotSentRow), findsNothing);

    await tester.pump(sendStallLimit);
    await harness.settle(tester);

    expect(find.byType(NotSentRow), findsOneWidget);
  });
}
