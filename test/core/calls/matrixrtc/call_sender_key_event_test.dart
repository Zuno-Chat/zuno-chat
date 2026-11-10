import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/call_sender_key_event.dart';

import '../../../helpers/call_fixtures.dart';

void main() {
  final key = keyBytes();

  test('a sender key travels as Zuno\'s own to-device type', () {
    expect(callSenderKeyEventType, 'im.zuno.call.sender_key');
  });

  test('a built sender key reads back as the same key', () {
    final content = buildSenderKeyContent(
      callId: 'call1',
      key: (epoch: 1700, gen: 3, key: key),
    );

    expect(content, {
      'call_id': 'call1',
      'epoch': 1700,
      'gen': 3,
      'key': base64Encode(key),
    });
    final parsed = parseSenderKeyContent(content, callId: 'call1');
    expect(parsed?.epoch, 1700);
    expect(parsed?.gen, 3);
    expect(parsed?.key, key);
  });

  for (final (reason, content) in <(String, Map<String, Object?>)>[
    (
      'another call',
      {'call_id': 'call0', 'epoch': 1, 'gen': 1, 'key': base64Encode(key)},
    ),
    (
      'a gen below 1',
      {'call_id': 'call1', 'epoch': 1, 'gen': 0, 'key': base64Encode(key)},
    ),
    (
      'a negative epoch',
      {'call_id': 'call1', 'epoch': -1, 'gen': 1, 'key': base64Encode(key)},
    ),
    (
      'a gen that is not a number',
      {'call_id': 'call1', 'epoch': 1, 'gen': '1', 'key': base64Encode(key)},
    ),
    ('no key', {'call_id': 'call1', 'epoch': 1, 'gen': 1}),
    (
      'a key that is not base64',
      {'call_id': 'call1', 'epoch': 1, 'gen': 1, 'key': '%%%'},
    ),
    (
      'a key of the wrong length',
      {
        'call_id': 'call1',
        'epoch': 1,
        'gen': 1,
        'key': base64Encode(key.sublist(0, 16)),
      },
    ),
  ]) {
    test('ignores $reason', () {
      expect(parseSenderKeyContent(content, callId: 'call1'), isNull);
    });
  }
}
