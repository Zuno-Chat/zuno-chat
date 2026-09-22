import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/send_failure.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  final client = buildTestClient(userId: '@me:example.org');
  final room = buildTestRoom(client);

  Event withStatus(EventStatus status) => Event(
    eventId: 'txid-1',
    type: EventTypes.Message,
    senderId: '@me:example.org',
    originServerTs: DateTime.now(),
    content: const {'msgtype': 'm.video', 'body': 'video.mp4'},
    status: status,
    room: room,
  );

  group('isDiscardablePlaceholder', () {
    test('a placeholder still sending or already failed is discardable', () {
      expect(isDiscardablePlaceholder(withStatus(EventStatus.sending)), isTrue);
      expect(isDiscardablePlaceholder(withStatus(EventStatus.error)), isTrue);
    });

    test('a sent event is never touched', () {
      expect(isDiscardablePlaceholder(withStatus(EventStatus.sent)), isFalse);
      expect(isDiscardablePlaceholder(withStatus(EventStatus.synced)), isFalse);
    });

    test('nothing to discard when the event is missing', () {
      expect(isDiscardablePlaceholder(null), isFalse);
    });
  });

  test('tooLargeToSendMessage names the server limit in whole megabytes', () {
    expect(
      tooLargeToSendMessage(FileTooBigMatrixException(110000000, 52428800)),
      'Too large to send. The limit is 52 MB.',
    );
  });
}
