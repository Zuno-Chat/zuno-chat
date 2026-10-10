import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/matrix/linkified_text.dart';

import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late bool refuseReports;

  setUp(() {
    refuseReports = false;
    harness = RoomPageHarness();
    harness.respond = (request) =>
        refuseReports && request.url.path.contains('/report/')
        ? http.Response(
            jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Slow down'}),
            429,
          )
        : null;
  });

  Iterable<http.Request> reports() =>
      harness.httpRequests.where((r) => r.url.path.contains('/report/'));

  Future<void> reportAsSpam(WidgetTester tester) async {
    harness.db.events = [harness.message(r'$bad', body: 'the private words')];
    await harness.pumpRoomPage(tester);

    await tester.longPress(find.byType(LinkifiedText));
    await harness.settle(tester);
    await tester.tap(find.text('Report'));
    await harness.settle(tester);
    expect(find.text('Report message'), findsOneWidget);
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await harness.settle(tester);
  }

  testWidgets('reports a message from someone else without its content', (
    tester,
  ) async {
    await reportAsSpam(tester);

    expect(
      reports().single.url.path,
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(harness.room.id)}'
      '/report/${Uri.encodeComponent(r'$bad')}',
    );
    expect(jsonDecode(reports().single.body), {'reason': 'spam'});
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('a refused report stays open and confirms nothing', (
    tester,
  ) async {
    refuseReports = true;

    await reportAsSpam(tester);

    expect(find.text('The report was not sent. Try again.'), findsOneWidget);
    expect(find.text('Report sent'), findsNothing);
  });
}
