import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/matrixrtc/call_encryption_key_event.dart';

void main() {
  test('round-trips a key through build/parse', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final content = buildCallEncryptionKeyContent(callId: 'call1', key: key);
    final parsed = parseCallEncryptionKeyContent(
      content: content,
      callId: 'call1',
    );
    expect(parsed, key);
  });

  test('null for a different call ID (stray/unrelated event)', () {
    final key = Uint8List.fromList([1, 2, 3]);
    final content = buildCallEncryptionKeyContent(callId: 'call1', key: key);
    expect(
      parseCallEncryptionKeyContent(content: content, callId: 'call2'),
      isNull,
    );
  });

  test('null for a malformed key payload (not valid base64)', () {
    expect(
      parseCallEncryptionKeyContent(
        content: {'call_id': 'call1', 'key': 'not valid base64!!'},
        callId: 'call1',
      ),
      isNull,
    );
  });

  test('null when the key field is missing entirely', () {
    expect(
      parseCallEncryptionKeyContent(
        content: {'call_id': 'call1'},
        callId: 'call1',
      ),
      isNull,
    );
  });

  test('round-trips a 0-length key', () {
    final key = Uint8List(0);
    final content = buildCallEncryptionKeyContent(callId: 'call1', key: key);
    expect(content['key'], '');
    final parsed = parseCallEncryptionKeyContent(
      content: content,
      callId: 'call1',
    );
    expect(parsed, isNotNull);
    expect(parsed, isEmpty);
  });

  test('an unusually-sized key (not 32 bytes) still parses — no length enforcement', () {
    for (final length in [1, 16, 33, 64]) {
      final key = Uint8List.fromList(List.generate(length, (i) => i % 256));
      final content = buildCallEncryptionKeyContent(callId: 'call1', key: key);
      final parsed = parseCallEncryptionKeyContent(
        content: content,
        callId: 'call1',
      );
      expect(parsed, key, reason: 'length $length');
    }
  });

  test('null when call_id is present but not a String', () {
    expect(
      parseCallEncryptionKeyContent(
        content: {'call_id': 42, 'key': base64Encode([1, 2, 3])},
        callId: 'call1',
      ),
      isNull,
    );
  });

  test('a null key field takes the same path as a missing one', () {
    expect(
      parseCallEncryptionKeyContent(
        content: {'call_id': 'call1', 'key': null},
        callId: 'call1',
      ),
      isNull,
    );
  });

  test('a call_id with special characters is still a plain string equality check', () {
    final key = Uint8List.fromList([9, 9, 9]);
    const weirdId = 'call:with/special!chars 🎉 and\nnewline';
    final content = buildCallEncryptionKeyContent(callId: weirdId, key: key);
    expect(
      parseCallEncryptionKeyContent(content: content, callId: weirdId),
      key,
    );
    expect(
      parseCallEncryptionKeyContent(content: content, callId: 'call1'),
      isNull,
    );
  });

  test('binary key content round-trips exactly byte-for-byte, base64 edge bytes included', () {
    final key = Uint8List.fromList([
      0x00,
      0xFF,
      0x00,
      0xFF,
      0x7F,
      0x80,
      ...List.generate(26, (i) => (i * 37) % 256),
    ]);
    expect(key, hasLength(32));
    final content = buildCallEncryptionKeyContent(callId: 'call1', key: key);
    final parsed = parseCallEncryptionKeyContent(
      content: content,
      callId: 'call1',
    );
    expect(parsed, isNotNull);
    expect(parsed!.toList(), key.toList());
  });

  test('the built content map has exactly call_id/key, nothing else', () {
    final key = Uint8List.fromList([1, 2, 3]);
    final content = buildCallEncryptionKeyContent(callId: 'call1', key: key);
    expect(content.keys.toSet(), {'call_id', 'key'});
    expect(content['call_id'], 'call1');
    expect(content['key'], isA<String>());
    expect(content['key'], base64Encode(key));
  });
}
