import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/notifications/message_notification_image.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;
  late Event event;

  setUp(() {
    client = Client('test', database: FakeDatabaseApi());
    client.setUserId('@me:x');
    room = buildTestRoom(client);
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

  test('returns null when the download exceeds the timeout', () async {
    final result = await fetchMessageNotificationImage(
      event,
      download: () => Future.delayed(
        const Duration(milliseconds: 50),
        () => MatrixFile(bytes: Uint8List(0), name: 'thumb.jpg'),
      ),
      timeout: const Duration(milliseconds: 5),
    );

    expect(result, isNull);
  });
}
