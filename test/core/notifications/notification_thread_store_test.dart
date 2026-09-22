import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/notification_thread_store.dart';

NotificationLine _line(String eventId, {String text = 'hi'}) =>
    NotificationLine(
      eventId: eventId,
      senderId: '@a:x',
      senderName: 'Alice',
      text: text,
      timestamp: DateTime.utc(2031, 1, 1, 12),
    );

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('round-trips a thread with its lines', () async {
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!r:x',
        title: 'Alice',
        isGroupChat: false,
        lines: [
          _line(r'$1'),
          _line(r'$2', text: 'there?'),
        ],
      ),
    );

    final thread = readNotificationThread(prefs, '!r:x');
    expect(thread?.title, 'Alice');
    expect(thread?.isGroupChat, isFalse);
    expect(thread?.lines.map((l) => l.text), ['hi', 'there?']);
    expect(thread?.lines.first.timestamp, DateTime.utc(2031, 1, 1, 12));
  });

  test('is empty for a room never posted', () {
    expect(readNotificationThread(prefs, '!nope:x'), isNull);
  });

  test('keeps only the newest lines', () async {
    final thread = NotificationThread(
      roomId: '!r:x',
      title: 'Alice',
      isGroupChat: false,
      lines: [for (var i = 0; i < maxNotificationLines + 3; i++) _line('\$$i')],
    );
    await writeNotificationThread(prefs, thread);

    final stored = readNotificationThread(prefs, '!r:x')!;
    expect(stored.lines, hasLength(maxNotificationLines));
    expect(stored.lines.last.eventId, '\$${maxNotificationLines + 2}');
  });

  test('clearing one room leaves the others', () async {
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!a:x',
        title: 'A',
        isGroupChat: false,
        lines: [_line(r'$1')],
      ),
    );
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!b:x',
        title: 'B',
        isGroupChat: true,
        lines: [_line(r'$2')],
      ),
    );

    await clearNotificationThread(prefs, '!a:x');

    expect(readNotificationThread(prefs, '!a:x'), isNull);
    expect(readNotificationThread(prefs, '!b:x'), isNotNull);
  });

  test('clearing everything forgets every room', () async {
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!a:x',
        title: 'A',
        isGroupChat: false,
        lines: [_line(r'$1')],
      ),
    );

    await clearAllNotificationThreads(prefs);

    expect(readNotificationThread(prefs, '!a:x'), isNull);
  });

  test('survives a corrupt store rather than crashing the post', () async {
    await prefs.setString(notificationThreadsKey, 'not json');

    expect(readNotificationThread(prefs, '!a:x'), isNull);
  });

  test('a placeholder line is remembered as one', () async {
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!r:x',
        title: 'Alice',
        isGroupChat: false,
        lines: [
          NotificationLine(
            eventId: r'$1',
            senderId: '@a:x',
            senderName: 'Alice',
            text: 'New message',
            timestamp: DateTime.utc(2031),
            placeholder: true,
          ),
        ],
      ),
    );

    expect(
      readNotificationThread(prefs, '!r:x')?.lines.single.placeholder,
      isTrue,
    );
  });

  test('round-trips an image attached to a line', () async {
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: '!r:x',
        title: 'Alice',
        isGroupChat: false,
        lines: [
          NotificationLine(
            eventId: r'$1',
            senderId: '@a:x',
            senderName: 'Alice',
            text: 'a cat',
            timestamp: DateTime.utc(2031),
            imageUri: 'content://zuno/1',
            imageMimeType: 'image/jpeg',
          ),
        ],
      ),
    );

    final line = readNotificationThread(prefs, '!r:x')!.lines.single;
    expect(line.imageUri, 'content://zuno/1');
    expect(line.imageMimeType, 'image/jpeg');
  });
}
