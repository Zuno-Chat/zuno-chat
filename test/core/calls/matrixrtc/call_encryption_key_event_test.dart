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

  test('the built content carries exactly the call id and the base64 key', () {
    final key = Uint8List.fromList([1, 2, 3]);
    expect(buildCallEncryptionKeyContent(callId: 'call1', key: key), {
      'call_id': 'call1',
      'key': base64Encode(key),
    });
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
}
