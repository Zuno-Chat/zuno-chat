import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/rooms/presentation/last_message_preview.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    final client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    client.setUserId('@me:example.org');
    room = buildTestRoom(client)..partial = false;
  });

  Future<void> pump(WidgetTester tester, Event? event) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(
          body: DefaultTextStyle.merge(
            style: zunoLightTheme.textTheme.bodyMedium,
            child: LastMessagePreview(room: room, event: event),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Event message(Map<String, Object?> content) => buildTestEvent(
    room,
    eventId: r'$e',
    senderId: '@bob:example.org',
    content: content,
  );

  testWidgets('a text preview is strut-locked to the inherited style', (
    tester,
  ) async {
    await pump(tester, message({'msgtype': 'm.text', 'body': 'สวัสดี'}));

    final text = tester.widget<Text>(find.text('สวัสดี'));
    expect(text.strutStyle?.forceStrutHeight, isTrue);
    expect(text.strutStyle?.fontSize, 14);
  });

  testWidgets('an icon-and-label preview is strut-locked too', (tester) async {
    await pump(
      tester,
      message({'msgtype': 'm.image', 'body': 'photo.jpg', 'url': 'mxc://x/y'}),
    );

    final texts = tester.widgetList<Text>(find.byType(Text));
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(text.strutStyle?.forceStrutHeight, isTrue);
    }
  });

  testWidgets('no last event says so, strut-locked', (tester) async {
    await pump(tester, null);

    final text = tester.widget<Text>(find.text('No messages'));
    expect(text.strutStyle?.forceStrutHeight, isTrue);
  });
}
