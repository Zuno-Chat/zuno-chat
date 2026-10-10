import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/notifications/message_notification_image.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Event event;

  setUp(() {
    final room = buildTestRoom(buildTestClient(userId: '@me:x'));
    event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@a:x',
      content: {
        'msgtype': MessageTypes.Image,
        'body': 'photo.jpg',
        'filename': 'photo.jpg',
        'url': 'mxc://x/photo',
      },
    );
  });

  test('returns the downloaded bytes and their type on success', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final result = await fetchMessageNotificationImage(
      event,
      download: () async => MatrixFile(bytes: bytes, name: 'thumb.jpg'),
    );

    expect(result?.bytes, bytes);
    expect(result?.mimeType, 'image/jpeg');
  });

  test('returns null when the download throws', () async {
    final result = await fetchMessageNotificationImage(
      event,
      download: () async => throw Exception('offline'),
    );

    expect(result, isNull);
  });

  test('gives up with null once the download outlasts the timeout', () {
    fakeAsync((async) {
      var done = false;
      NotificationImage? result;
      fetchMessageNotificationImage(
        event,
        download: () => Completer<MatrixFile>().future,
      ).then((image) {
        result = image;
        done = true;
      });

      async.elapse(
        messageNotificationImageTimeout - const Duration(milliseconds: 1),
      );
      expect(done, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(done, isTrue);
      expect(result, isNull);
    });
  });
}
