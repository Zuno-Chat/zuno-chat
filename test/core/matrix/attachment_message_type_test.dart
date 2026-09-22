import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/attachment_message_type.dart';

void main() {
  for (final type in [
    MessageTypes.Image,
    MessageTypes.Sticker,
    MessageTypes.Video,
    MessageTypes.Audio,
    MessageTypes.File,
  ]) {
    test('$type is an attachment message type', () {
      expect(isAttachmentMessageType(type), isTrue);
    });
  }

  test('plain text is not an attachment message type', () {
    expect(isAttachmentMessageType(MessageTypes.Text), isFalse);
  });

  test('an unrecognized/custom msgtype is not an attachment message type', () {
    expect(isAttachmentMessageType('im.zuno.call_summary'), isFalse);
  });
}
