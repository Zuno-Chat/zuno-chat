import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/chat/data/unsent.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  final me = buildTestClient(userId: '@me:example.org');
  final chat = buildTestRoom(me, id: '!a:example.org');
  final clip = (
    bytes: Uint8List.fromList('OggS'.codeUnits),
    duration: const Duration(seconds: 4),
    waveform: const [1, 2, 3],
  );

  test('keeps what was typed in a chat for that chat', () {
    final unsent = Unsent()..keepText(chat, 'half a thought');

    expect(unsent.textOf(chat), 'half a thought');
    expect(unsent.textOf(buildTestRoom(me, id: '!b:example.org')), '');
  });

  test('keeps it for the account that typed it', () {
    final other = buildTestClient(userId: '@other:example.org');
    final unsent = Unsent()..keepText(chat, 'half a thought');

    expect(unsent.textOf(buildTestRoom(other, id: chat.id)), '');
  });

  test('forgets text that is only blank', () {
    final unsent = Unsent()
      ..keepText(chat, 'half a thought')
      ..keepText(chat, '  ');

    expect(unsent.textOf(chat), '');
  });

  test('keeps a recording in its chat for the account that made it', () {
    final other = buildTestClient(userId: '@other:example.org');
    final unsent = Unsent()..keepVoice(chat, clip);

    expect(unsent.voiceOf(chat), same(clip));
    expect(unsent.voiceOf(buildTestRoom(me, id: '!b:example.org')), isNull);
    expect(unsent.voiceOf(buildTestRoom(other, id: chat.id)), isNull);
  });

  test('a recording and text wait side by side, and each goes on its own', () {
    final unsent = Unsent()
      ..keepText(chat, 'half a thought')
      ..keepVoice(chat, clip)
      ..keepVoice(chat, null);

    expect(unsent.voiceOf(chat), isNull);
    expect(unsent.textOf(chat), 'half a thought');
  });
}
