import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/data/typing_announcer.dart';

import '../presentation/room_page_harness.dart';

void main() {
  late RoomPageHarness harness;
  late TextEditingController input;
  late bool enabled;
  late TypingAnnouncer announcer;

  setUp(() {
    harness = RoomPageHarness();
    input = TextEditingController();
    enabled = true;
    announcer = TypingAnnouncer(
      room: harness.room,
      input: input,
      enabled: () => enabled,
    );
    addTearDown(input.dispose);
  });

  Iterable<Map<String, Object?>> typing() => harness.httpRequests
      .where((r) => r.url.path.contains('/typing/'))
      .map((r) => jsonDecode(r.body) as Map<String, Object?>);

  testWidgets('is announced while writing and withdrawn once cleared', (
    tester,
  ) async {
    input.text = 'hel';
    await harness.settle(tester);
    expect(typing().single, containsPair('typing', true));

    input.text = '';
    await harness.settle(tester);
    expect(typing().last, {'typing': false});
    announcer.dispose();
  });

  testWidgets('is refreshed while writing goes on, and dropped after a '
      'pause', (tester) async {
    input.text = 'hel';
    await harness.settle(tester);
    input.text = 'hell';
    await tester.pump(const Duration(seconds: 4));
    input.text = 'hello';
    await tester.pump(const Duration(seconds: 4));
    input.text = 'hello!';
    await tester.pump(const Duration(seconds: 3));
    await harness.settle(tester);
    expect(typing().where((t) => t['typing'] == true), hasLength(2));

    await tester.pump(const Duration(seconds: 6));
    await harness.settle(tester);
    expect(typing().last, {'typing': false});
    announcer.dispose();
  });

  testWidgets('is withdrawn when the chat closes mid-sentence', (tester) async {
    input.text = 'hel';
    await harness.settle(tester);

    announcer.dispose();
    await harness.settle(tester);

    expect(typing().last, {'typing': false});
  });

  testWidgets('says nothing while the setting is off', (tester) async {
    enabled = false;

    input.text = 'hello';
    await harness.settle(tester);
    announcer.dispose();
    await harness.settle(tester);

    expect(typing(), isEmpty);
  });
}
