import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/image_caption.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient());
  });

  test('body different from filename is a real caption', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: {'filename': 'photo.jpg', 'body': 'Look at this!'},
    );
    expect(imageCaption(event), 'Look at this!');
  });

  test('body equal to filename means no caption', () {
    final event = buildTestEvent(
      room,
      eventId: r'$2',
      senderId: '@a:x',
      content: {'filename': 'photo.jpg', 'body': 'photo.jpg'},
    );
    expect(imageCaption(event), isNull);
  });

  test('missing filename means no caption (not attachment-shaped content)', () {
    final event = buildTestEvent(
      room,
      eventId: r'$3',
      senderId: '@a:x',
      content: {'body': 'photo.jpg'},
    );
    expect(imageCaption(event), isNull);
  });
}
