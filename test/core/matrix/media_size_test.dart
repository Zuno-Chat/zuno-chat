import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/media_size.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  Event withInfo(Map<String, Object?> info) => buildTestEvent(
    buildTestRoom(buildTestClient()),
    eventId: r'$photo',
    senderId: '@alice:example.org',
    content: {'msgtype': MessageTypes.Video, 'body': 'clip.mp4', 'info': info},
  );

  test('reads size, dimensions and duration from the attachment info', () {
    final event = withInfo({'w': 1280, 'h': 720, 'duration': 4500, 'size': 9});

    expect((event.mediaWidth, event.mediaHeight), (1280, 720));
    expect(event.mediaDuration, const Duration(milliseconds: 4500));
    expect(event.fileSize, 9);
  });

  test('missing or malformed info reads as unknown', () {
    final event = withInfo({'w': '1280', 'duration': 'long'});

    expect((event.mediaWidth, event.mediaHeight), (null, null));
    expect(event.mediaDuration, isNull);
    expect(event.fileSize, isNull);
  });

  test('a size needs both sides above zero', () {
    expect(mediaSize(1280, 720), (1280, 720));
    expect(mediaSize(0, 720), isNull);
    expect(mediaSize(1280, null), isNull);
  });
}
